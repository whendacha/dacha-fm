#!/usr/bin/env python3
"""Check the public-catalog release and its deployed dependencies without credentials.

Run from any directory: python3 ios/scripts/preflight_public_release.py [--json]
This checks availability and configuration, not wallet approval or App Review readiness.
"""

import argparse
import hashlib
from html.parser import HTMLParser
import ipaddress
import json
from pathlib import Path
import plistlib
import re
import socket
import ssl
import sys
from urllib.error import HTTPError
from urllib.parse import urlencode, urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, HTTPSHandler, Request, build_opener


ROOT = Path(__file__).resolve().parents[2]
SETTINGS = ("MOBILE_API_BASE_URL", "METEOR_BRIDGE_URL", "PRIVACY_POLICY_URL", "SUPPORT_URL")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def config_values(path, visited=None):
    """Resolve this project's simple xcconfig assignments and ordered includes."""
    visited = set() if visited is None else visited
    require(path not in visited, "Recursive xcconfig include")
    visited.add(path)
    values = {}
    for line in path.read_text().splitlines():
        line = line.split("//", 1)[0].strip()
        include = re.fullmatch(r'#include(\?)?\s+"([^\"]+)"', line)
        if include:
            child = path.parent / include[2]
            if child.exists():
                values.update(config_values(child.resolve(), visited))
            else:
                require(include[1], f"Required xcconfig include missing: {child.name}")
            continue
        assignment = re.fullmatch(r"([A-Z_]+)\s*=\s*(.*)", line)
        if assignment and assignment[1] in SETTINGS:
            value = assignment[2].replace("$()", "").strip().strip('"')
            require("$(" not in value, f"Unresolved xcconfig variable: {assignment[1]}")
            values[assignment[1]] = value
    visited.remove(path)
    return values


def public_https(url):
    parts = urlsplit(url)
    require(parts.scheme == "https" and parts.hostname, "Endpoint must use HTTPS")
    require(not parts.username and not parts.password and not parts.fragment,
            "Endpoint must not contain credentials or a fragment")
    require(parts.port in (None, 443), "Endpoint must use the standard HTTPS port")
    host = parts.hostname.lower()
    require(not any(host == item or host.endswith("." + item) for item in
                    ("localhost", "local", "invalid", "test", "example", "example.com", "example.org", "example.net")),
            "Placeholder or local endpoint is not suitable for release")
    addresses = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    require(addresses and all(ipaddress.ip_address(item[4][0]).is_global for item in addresses),
            "Endpoint resolved to a non-public address")
    return url


class HTTPSRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        public_https(newurl)
        return super().redirect_request(request, fp, code, message, headers, newurl)


TLS = ssl.create_default_context()
# python.org macOS installs may lack their optional certificate bundle. Use the
# OS trust bundle when present; certificate and hostname verification stay on.
if not ssl.get_default_verify_paths().cafile and Path("/etc/ssl/cert.pem").is_file():
    TLS.load_verify_locations(cafile="/etc/ssl/cert.pem")
OPENER = build_opener(HTTPSHandler(context=TLS), HTTPSRedirects())  # No cookies or auth handlers.


def fetch(url, *, method="GET", limit=2_000_000, byte_range=False):
    public_https(url)
    headers = {"User-Agent": "DachaFM-ReleasePreflight/1.0", "Accept": "*/*"}
    if byte_range:
        headers["Range"] = "bytes=0-2047"
    with OPENER.open(Request(url, headers=headers, method=method), timeout=20) as response:
        status, content_type = response.status, response.headers.get_content_type()
        if method == "HEAD":
            body = b""
        elif byte_range:
            body = response.read(2048)  # Close even when a server ignores Range.
        else:
            body = response.read(limit + 1)
            require(len(body) <= limit, "Response exceeded the preflight size limit")
        return status, content_type, body


class PageAssets(HTMLParser):
    def __init__(self):
        super().__init__()
        self.scripts, self.styles = [], []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "script" and attributes.get("src"):
            self.scripts.append(attributes["src"])
        if tag == "link" and attributes.get("rel") == "stylesheet":
            self.styles.append(attributes.get("href", ""))


def match(pattern, text, description):
    found = re.search(pattern, text)
    require(found, f"Could not derive {description} from the current app source")
    return found[1]


def run():
    results = []
    values = config_values(ROOT / "ios/Config/Release.xcconfig")
    require(all(key in values for key in SETTINGS), "Release is missing a required configuration key")
    require(values["MOBILE_API_BASE_URL"] == "", "Release must select public catalog mode with an empty mobile backend URL")
    app_source = (ROOT / "ios/NearFM/App/AppModel.swift").read_text()
    require(re.search(r"var usesPublicCatalog:\s*Bool\s*\{\s*baseURL == nil\s*\}", app_source),
            "App public-catalog selection changed; update this preflight")
    with (ROOT / "ios/NearFM/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    for name, setting in (("MobileAPIBaseURL", SETTINGS[0]), ("MeteorBridgeURL", SETTINGS[1]),
                          ("PrivacyPolicyURL", SETTINGS[2]), ("SupportURL", SETTINGS[3])):
        require(info.get(name) == f"$({setting})", f"Info.plist does not use {setting}")
    results.append({"check": "release_public_catalog", "status": "pass"})

    base = public_https(values["METEOR_BRIDGE_URL"])
    require(not urlsplit(base).query, "Bridge base URL must not contain a query")
    page_url = base.rstrip("/") + "/mobile/auth/"
    status, kind, html = fetch(page_url, limit=100_000)
    require(status == 200 and kind == "text/html" and b"Dacha FM" in html, "Bridge HTML is missing or invalid")
    assets = PageAssets()
    assets.feed(html.decode("utf-8"))
    require(assets.scripts == ["./bridge.js"] and assets.styles == ["./style.css"],
            "Bridge must load the expected local JS and CSS")
    for filename in ("style.css", "bridge.js"):
        status, kind, body = fetch(urljoin(page_url, filename))
        require(status == 200 and body, f"Bridge asset unavailable: {filename}")
        require(kind in ({"text/css"} if filename.endswith(".css") else {"application/javascript", "text/javascript"}),
                f"Incorrect content type for {filename}: {kind}")
        local = (ROOT / "docs/mobile/auth" / filename).read_bytes()
        digest = hashlib.sha256(body).hexdigest()
        require(digest == hashlib.sha256(local).hexdigest(), f"Deployed {filename} differs from the generated local asset")
        results.append({"check": filename, "status": "pass", "sha256": digest, "bytes": len(body)})
    results.append({"check": "bridge_html", "status": "pass", "url": page_url})

    for key in ("PRIVACY_POLICY_URL", "SUPPORT_URL"):
        status, kind, body = fetch(values[key], limit=200_000)
        require(status == 200 and kind == "text/html" and b"Dacha FM" in body, f"Public page unavailable: {key}")
        results.append({"check": key.lower(), "status": "pass", "url": values[key]})

    source = (ROOT / "ios/NearFM/Services/PublicCatalog.swift").read_text()
    catalog_base = match(r'private let baseURL = URL\(string: "([^\"]+)"\)', source, "catalog origin")
    path = match(r'return try await read\(path: "([^\"]+)", query: items\)', source, "catalog path")
    sort = match(r'URLQueryItem\(name: "sort", value: "([^\"]+)"\)', source, "catalog sort")
    page_size = int(match(r'private let pageSize = (\d+)', source, "catalog page size"))
    url = catalog_base.rstrip("/") + "/" + path + "?" + urlencode({"sort": sort, "page": 1, "limit": page_size})
    status, kind, body = fetch(url, limit=3_000_000)
    require(status == 200 and kind == "application/json", "Catalog did not return JSON")
    payload = json.loads(body)
    require(isinstance(payload, dict) and payload.get("page") == 1 and payload.get("limit") == page_size
            and isinstance(payload.get("songs"), list), "Catalog pagination shape does not match the app")
    playable = []
    for song in payload["songs"]:
        require(isinstance(song, dict), "Catalog contains a non-object song")
        for field in ("uuid", "title", "uploader_account_id"):
            require(isinstance(song.get(field), str), f"Song is missing its required {field} string")
        require(type(song.get("uploader_id")) is int, "Song uploader_id is not an integer")
        if (song["uuid"] and song["title"].strip() and song["uploader_account_id"] and song["uploader_id"] > 0
                and song.get("is_hidden") is not True and song.get("is_deleted") is not True
                and song.get("is_validated") is not False and isinstance(song.get("audio_url"), str)
                and urlsplit(song["audio_url"]).scheme == "https"):
            playable.append(song)
    require(playable, "First catalog page has no playable HTTPS track")
    audio_url = playable[0]["audio_url"]
    try:
        status, kind, _ = fetch(audio_url, method="HEAD")
        probe = "HEAD"
    except HTTPError as error:
        if error.code not in (405, 501):
            raise
        status, kind, _ = fetch(audio_url, byte_range=True)
        probe = "GET bytes=0-2047"
    require(status in (200, 206) and kind.startswith("audio/"), "First playable track did not return an audio response")
    results.append({"check": "live_catalog", "status": "pass", "songs": len(payload["songs"]), "playable": len(playable),
                    "first_track_id": playable[0]["uuid"], "audio_probe": probe, "audio_content_type": kind})
    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Print a machine-readable report")
    arguments = parser.parse_args()
    try:
        checks = run()
        report = {"status": "pass", "checks": checks,
                  "limits": "Does not prove live wallet approval, full audio playback, catalog licensing, or App Review readiness."}
    except Exception as error:
        report = {"status": "fail", "error": str(error)}
    if arguments.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    elif report["status"] == "pass":
        for check in report["checks"]:
            print("PASS", check["check"])
        print(report["limits"])
    else:
        print("FAIL", report["error"], file=sys.stderr)
    sys.exit(0 if report["status"] == "pass" else 1)
