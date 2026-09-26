# Dacha FM build 4 App Privacy audit

Audit date: 26 September 2026. Scope: Dacha FM 1.0.0 (4) source, service configuration and retained Supabase log fields. All six categories below are now configured in the App Store Connect draft, linked to the user, for App Functionality and without tracking; Product Interaction also has Product Personalization. **The declaration is not published**, pending unresolved external search/provider-retention practices. App Review is not submitted.

## Configured App Store Connect draft

| Apple category | Evidence and scope | Linked to user | Purpose | Tracking |
| --- | --- | --- | --- | --- |
| User ID | Public wallet account ID and account-linked session identifiers | Yes | App Functionality | No |
| Other User Content | Cloud playlist names, track selections and their order, personal library | Yes | App Functionality | No |
| Product Interaction | Cloud favorites and hidden-artist preferences | Yes | App Functionality; Product Personalization | No |
| Coarse Location | Supabase gateway retains city and country derived from IP | Yes | App Functionality, including security | No |
| Other Diagnostic Data | Retained IP, HTTP request metadata, user-agent, status codes and security network fingerprints | Yes | App Functionality, including service operation and security | No |
| Performance Data | Retained function request execution durations | Yes | App Functionality | No |

The cloud library is explicitly associated with a wallet account. Provider request metadata retains the source IP without verified anonymization, so an unlinked-data assertion is not supported. Provider security fingerprints do not by themselves establish advertising tracking or collection of an advertising identifier. No advertising SDK or cross-service advertising use was found in the reviewed implementation.

Apple requires disclosure of data retained beyond servicing a request, including relevant partner practices. Its category definitions cover account identifiers, free-form user content, app interactions and diagnostics; cloud sync remains disclosure-relevant even though sign-in is optional. Source: [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/).

## Source evidence

- `ios/Packages/NearFMCore/Sources/NearFMCore/Models.swift`: `LibrarySnapshot` contains favorites, playlists and blocked artist IDs; playlists contain their names, ordered tracks and metadata URLs.
- `supabase/migrations/20260926050001_dacha_cloud_library.sql`: account-keyed library storage, hashed session tokens, expiring challenges, forced row-level security and service-only RPC grants. Account deletion cascades to the library and sessions.
- `supabase/functions/dacha-cloud/handler.mjs`: verifies wallet proof and mainnet key ownership, transmits the public account ID/key to the RPC, hashes session tokens, and avoids application logging of requests or proofs.
- `ios/NearFM/Services/Authentication.swift`: session stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; private wallet keys and seed phrases are not requested.
- `ios/NearFM/App/AppModel.swift` and `ios/NearFM/Views/SettingsView.swift`: optional cloud sign-in, guest library isolation, sign-out and in-app account deletion.
- `ios/NearFM/Services/PublicCatalog.swift`: public requests use a cookie-free ephemeral session without cloud credentials. Song searches transmit `q` to `api.near.fm`; artist lookup paths can contain an artist slug.
- `ios/NearFM/Playback/AudioPlayer.swift`: playback state is saved locally; HTTPS audio loads directly from the catalog-provided URL. No separate listening analytics were found.
- `mobile-bridge/src/main.js` and `protocol.mjs`: wallet proof returns in a URL fragment; challenge parameters are removed from browser history after parsing. The bridge requests an identity message, not transfers or contract permissions.

## Retained infrastructure data verified live

Read-only queries against Supabase project `clxaqzlecqiypyiwgkxd` inspected field names and aggregate presence counts, without retrieving raw IPs, wallet identifiers, signatures or tokens. In the default previous-24-hour window, all 31 function-edge events had nonempty fields for IP, city, country, user-agent, execution duration and a security network fingerprint.

The aggregate query was:

```sql
select count() as events,
       countIf(notEmpty(log_attributes['request.headers.cf_connecting_ip'])) as with_ip,
       countIf(notEmpty(log_attributes['request.cf.city'])) as with_city,
       countIf(notEmpty(log_attributes['request.cf.country'])) as with_country,
       countIf(notEmpty(log_attributes['request.headers.user_agent'])) as with_user_agent,
       countIf(notEmpty(log_attributes['execution_time_ms'])) as with_duration,
       countIf(notEmpty(log_attributes['request.cf.botManagement.ja4'])) as with_security_fingerprint
from logs
where source = 'function_edge_logs';
```

This is evidence of infrastructure retention even though the application handler has no request logger. [Supabase log field documentation](https://supabase.com/docs/guides/observability/log-field-reference) describes retained request metadata. [GitHub Pages documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages#data-collection) also states that visitors' IP addresses are logged for security.

## Retention, deletion and manifest

The cloud account and library remain until deletion. Sessions expire after 30 days; challenges expire after five minutes. Expired records are cleaned in bounded batches during later sign-in requests. Server account deletion removes the library and all sessions. Local copies on other devices can remain until removed there, and hosting-provider logs/backups follow separate retention policies. No unverified retention period is asserted.

The build 4 `ios/NearFM/Resources/PrivacyInfo.xcprivacy` still declares User ID and Other User Content only. The six-category ASC draft now reflects the known additional data; align any subsequent binary manifest with established practices. Public privacy and support pages are deployed, and their bytes retrieved with curl match the local files. The subsequent build 5 manifest is aligned to these six known categories, including Product Personalization for Product Interaction. The unresolved source-service retention question remains; this is not a completed public privacy declaration. Key values follow [Apple’s privacy-manifest reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype).

Required-reason API declaration `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1` matches the observed app-owned UserDefaults usage. The native app depends on Apple frameworks and its local Swift package; no native third-party analytics SDK was found.

## Unresolved external-retention questions

The external catalog receives search strings; external media hosts receive song/image paths. Upstream `server/src/main.rs` installs `TraceLayer::new_for_http()` and defaults `tower_http` logging to DEBUG. At that level full request URIs, including `q`, can appear in logs. The production log level and retention were not verified, so this is evidence of possible search logging, not proof of the live configuration. Do not assert that Search History or externally observed music access is never collected. Resolve those practices before publishing a definitive privacy declaration. This audit establishes neither catalog authorization nor a music-content license.

No evidence was found in the reviewed native app of contact access, GPS access, microphone recording, user audio uploads, payment collection, IDFA use or app crash analytics. Data processed exclusively on the device, including the guest library and playback position, is separate from collected cloud data.
