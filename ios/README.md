# Dacha FM for iPhone

Native SwiftUI listener for iOS 17+, developed in the [whendacha fork](https://github.com/whendacha/dacha-fm). Build 2 uses the public streaming catalog, author-only queues, editable playlists, favorites, guest listening, AVPlayer/lock-screen controls, author blocking, and optional Meteor Wallet identity verification.

Build 1 was delivered through TestFlight but lacked service configuration. Build 2 replaces that unavailable catalog with direct public streaming. All three simulator UI tests, signed packaging and deployed-service preflight passed. Apple received **1.0.0 (2)** at **07:50:32 MSK on 26 September 2026** and completed processing. It is available to the existing internal TestFlight group and its invited tester; Russian testing instructions are saved. Actual Meteor approval and the signed return on a physical iPhone remain unverified. See [release status](../docs/release/status.md).

## Default build 2 behavior

- Catalog requests go to `https://api.near.fm/api/songs`; audio and artwork load from the HTTPS URLs in the response. No Dacha account token or personal library is sent to the source, and audio is not copied into this repository or offered for offline download.
- Author queues filter by exact numeric uploader identity. Source pages contain at most 100 songs; each request scans at most three pages and returns the last consumed source page. Author discovery is incremental, not an exhaustive list from the first page. Song search and author-name search are handled separately; an exact author slug can also retrieve a public profile.
- Guest favorites, playlists and blocked authors persist on the iPhone. Meteor identity opens a separate on-device library for the verified mainnet account. Guest-library merging is explicit. There is no cloud synchronization in this mode.
- The static HTTPS bridge asks Meteor only to sign the fixed Dacha FM identity message. The app binds the proof to its nonce, state, recipient and five-minute lifetime, verifies its Ed25519 signature, then checks that the key is a mainnet FullAccess key for the claimed account. No transaction, contract permission, private key or seed phrase is requested.
- Sign in with Apple is available only in the optional owned-backend mode. Public-catalog reports direct the listener to the source or support; the app does not claim to have submitted a moderation report to an unconfigured backend.

## Build and test

Open `NearFM.xcodeproj` in Xcode. The shared scheme remains `NearFM`; the product is `DachaFM.app`, bundle ID `com.whendacha.dachafm`. The only Swift package is the local `Packages/NearFMCore`.

From the repository root:

```sh
swift test --package-path ios/Packages/NearFMCore
python3 ios/scripts/generate_project.py
xcodebuild -project ios/NearFM.xcodeproj -scheme NearFM \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/DerivedData CODE_SIGNING_ALLOWED=NO build
```

For UI tests, select an available simulator from `xcrun simctl list devices available`:

```sh
xcodebuild -project ios/NearFM.xcodeproj -scheme NearFM \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ios/DerivedData CODE_SIGNING_ALLOWED=NO test
```

Debug supports `--demo` and `--ui-test-store <UUID>` for deterministic local tests. Demo mode is visibly labeled and uses an original synthesized tone; it cannot establish successful login, synchronization, report delivery or real music playback. Normal Release builds use the public catalog when `MOBILE_API_BASE_URL` is empty. Session identity is stored in Keychain, and library files are separated by account and guest.

`scripts/generate_project.py` deterministically recreates the project and shared scheme after adding source/resources. `scripts/generate_resources.swift` recreates the original icon/tone. Keep app configuration in xcconfig files so regeneration preserves it.

## Public-mode configuration and static bridge

Debug and Release contain these defaults:

```xcconfig
MOBILE_API_BASE_URL =
METEOR_BRIDGE_URL = https:/$()/whendacha.github.io/dacha-fm
PRIVACY_POLICY_URL = https:/$()/whendacha.github.io/dacha-fm/privacy.html
SUPPORT_URL = https:/$()/whendacha.github.io/dacha-fm/support.html
```

`$()` prevents xcconfig from treating `//` as a comment. The bridge setting is a base URL, including the repository path for GitHub Pages; the app appends `/mobile/auth`. The native callback is `dachafm://auth/callback`. The static bridge returns the bounded proof in its URL fragment. It does not issue a backend session or PKCE code.

Build and publish the static bridge using [mobile-bridge/README.md](../mobile-bridge/README.md). GitHub Pages serves `docs/` over HTTPS at the configured URL, including its generated assets, privacy and support pages. Release preflight verified HTTP 200 responses and the exact deployed JavaScript hash. A simulator UI test exercised the real native browser Prepare/Confirm flow and reached Meteor's clean-wallet entry screen. An actual physical-iPhone Meteor approval and signed return remain a required end-to-end check.

The ignored `ios/Config/Local.xcconfig` can contain `DEVELOPMENT_TEAM = YOUR_TEAM_ID` and intentional local overrides. Never commit signing secrets or wallet credentials.

## Optional owned-backend mode

Setting `MOBILE_API_BASE_URL` selects the separate mobile API and its catalog instead of the public adapter. Deploy the Rust backend with `MOBILE_ONLY=true`, a separate migrated database, and the [mobile API configuration and moderation instructions](../docs/mobile-api.md). Its catalog remains empty until an operator approves tracks. This optional mode supplies private versioned cloud libraries, server report storage, revocable sessions, and independent Apple/Meteor accounts.

For that mode, deploy the Next.js route `web/src/app/mobile/auth/` on an owned HTTPS origin and configure its server-side `MOBILE_API_URL` and `MOBILE_NEAR_NETWORK`. Use this deployed origin for `METEOR_BRIDGE_URL`; the static local-identity bridge is not interchangeable with the server/PKCE bridge. The server bridge returns a one-time code, which the native app exchanges with its private PKCE verifier.

Sign in with Apple requires the matching bundle audience, Apple credentials and token-encryption configuration. Apple and Meteor server identities remain independent; account linking is not implemented. Server sessions expire after 30 days and require another login. These backend capabilities are not active merely because their code exists in the repository.

## Archive and upload

With a valid Apple Developer team and the intended configuration:

```sh
xcodebuild -project ios/NearFM.xcodeproj -scheme NearFM \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath ios/build/DachaFM.xcarchive \
  -allowProvisioningUpdates archive
```

Validate and distribute the signed archive to the matching App Store Connect record. Preserve Apple's upload receipt and processed build number before reporting delivery. Test real streams, author pagination, guest/account library separation, Meteor approval/return, logout/deletion, interruptions, headphones and background playback on a physical device. For App Review, complete the actual privacy disclosures, age rating, review access, content permissions and metadata; test any optional backend features before enabling them.

The inspected upstream commit `7aa4bad` has no explicit license. A public repository and accessible streams do not themselves establish distribution rights. Dacha FM uses its own product name; source/protocol attribution remains accurate. No license grant or Apple approval is asserted.
