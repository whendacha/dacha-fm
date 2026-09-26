# Dacha FM for iPhone

Native SwiftUI listener for iOS 17+, developed in the [whendacha fork](https://github.com/whendacha/dacha-fm). Build 5 adds reversible individual-song hiding with cloud synchronization. The English interface reserves space for the mini-player on every navigation screen so pagination and the last list rows remain reachable. It keeps public streaming, artist-only queues, editable playlists, favorites, guest listening, background audio and optional Meteor-authenticated cloud synchronization.

Apple accepted **1.0.0 (5)** at **13:34:10 MSK (10:34:10 UTC) on 26 September 2026**. Processing completed and the build is available to the existing internal TestFlight group with English testing instructions. Validation passed: 48 core tests, seven simulator UI tests, 15 Edge tests, 15 PostgreSQL tests, 14 live cloud checks and signed archive/export checks. The UI suite covers individual song hiding/restoration, pause/empty queue, large-text layout, real streaming and the Meteor entry screen. See [build 5 evidence](../docs/release/build-5-hidden-songs.md) and [release status](../docs/release/status.md). Physical-device Meteor approval, signed return and two-device synchronization remain acceptance checks; no App Review submission or approval is claimed.

Build 5 adds **Hide song** to song menus and the full player, and **Settings → Hidden songs → Unhide**. It removes a song from visible lists and playback while preserving its saved favorite/playlist membership. Other songs by the artist remain available. Hidden songs sync with the private library; legacy build 4 writes preserve the new field. See [cloud verification](../docs/release/build-5-cloud-verification.md).

## Default behavior

- Catalog requests go to `https://api.near.fm/api/songs`; audio and artwork load from the HTTPS URLs in the response. No Dacha account token or personal library is sent to the source, and audio is not copied into this repository or offered for offline download.
- Author queues filter by exact numeric uploader identity. Source pages contain at most 100 songs; each request scans at most three pages and returns the last consumed source page. Author discovery is incremental, not an exhaustive list from the first page. Song search and author-name search are handled separately; an exact author slug can also retrieve a public profile.
- Guest favorites, playlists, hidden songs and blocked authors persist on the iPhone without signing in. Signing in with the same Meteor mainnet account on another device selects the same private cloud library. Account and guest files stay separate; importing the guest library is an explicit action.
- The static HTTPS bridge asks Meteor to sign an explicit cloud-library statement. A server-issued five-minute nonce and native PKCE verifier bind the sign-in to the initiating app. The app verifies the bounded callback proof, and the cloud API independently verifies the signature, PKCE and mainnet FullAccess key before issuing a revocable 30-day session. The bridge never receives the native verifier or the cloud bearer token. No transaction, contract permission, private key or seed phrase is requested.
- Sign in with Apple is available only in the optional owned-backend mode. Public-catalog reports direct the listener to the source or support; the app does not claim to have submitted a moderation report to an unconfigured backend.

The cloud API is separate from the music source: `CLOUD_API_BASE_URL` handles private libraries and authentication while `MOBILE_API_BASE_URL` stays empty to keep the public catalog adapter. A cloud bearer token is never attached to public catalog, audio or artwork requests. The cloud stores library metadata and track URLs, not audio files.

## Synchronization and account changes

Edits save locally together with their pending-sync metadata before upload. Synchronization runs after sign-in, after edits, when the app becomes active, or when the listener taps the retry/sync control in Settings. Network failures preserve local edits across relaunch. Music still streams from its source; offline library editing does not provide offline audio downloads.

The app fetches the current cloud version before writing and uses compare-and-swap to detect concurrent changes. If both devices changed the library, Settings offers **Use cloud version** or **Use this iPhone's version**. This chooses a complete snapshot, including deletions, order, hidden songs and hidden authors; it does not silently merge conflicting versions. A lost response to an already-committed save is recognized when the cloud content matches the pending local content.

An expired or revoked cloud session requires another Meteor confirmation. Its local account library and pending edits remain accessible. Existing build 2 local wallet profiles show **Enable synchronization through Meteor**, preserving their saved library while requesting the distinct cloud sign-in statement.

Logout revokes the current cloud session and then shows the guest library; a network failure does not falsely report server logout. Account deletion requires server confirmation before the current device removes its account library. It deletes the cloud profile and library and revokes all of that account's server sessions. It does not delete the wallet, blockchain data, guest library, or cached files on another device. Other devices must authenticate again; a subsequent verified sign-in can create a new empty cloud profile.

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

Debug supports `--demo` and `--ui-test-store <UUID>` for deterministic local tests. The `--ui-test-layout` flag requires an isolated test-store UUID and supplies paginated songs and long guest-library lists; its fixtures are excluded from Release. Demo mode is visibly labeled and uses an original synthesized tone; it cannot establish successful login, synchronization, report delivery or real music playback. Normal Release builds use the public catalog when `MOBILE_API_BASE_URL` is empty. Session identity is stored in Keychain, and library files are separated by account and guest.

`scripts/generate_project.py` deterministically recreates the project and shared scheme after adding source/resources. `scripts/generate_resources.swift` recreates the original icon/tone. Keep app configuration in xcconfig files so regeneration preserves it.

## Public catalog, cloud and bridge configuration

Debug and Release contain these defaults:

```xcconfig
MOBILE_API_BASE_URL =
CLOUD_API_BASE_URL = https:/$()/clxaqzlecqiypyiwgkxd.supabase.co/functions/v1/dacha-cloud
METEOR_BRIDGE_URL = https:/$()/whendacha.github.io/dacha-fm
PRIVACY_POLICY_URL = https:/$()/whendacha.github.io/dacha-fm/privacy.html
SUPPORT_URL = https:/$()/whendacha.github.io/dacha-fm/support.html
```

`$()` prevents xcconfig from treating `//` as a comment. The bridge setting is a base URL, including the repository path for GitHub Pages; the app appends `/mobile/auth`. The native callback is `dachafm://auth/callback`. The static bridge returns the bounded proof in its URL fragment. The app sends that proof and its private PKCE verifier to the cloud API, which issues the session directly to the app. See [cloud deployment and tests](../supabase/README.md) and the [database contract](../supabase/DB_CONTRACT.md).

Build and publish the static bridge using [mobile-bridge/README.md](../mobile-bridge/README.md). GitHub Pages serves `docs/` over HTTPS at the configured URL, including generated assets, privacy and support pages. The bridge accepts both the build 2 local statement and the build 3 cloud statement; it rejects arbitrary messages. The deployed assets match the generated bundle. Build 3 simulator tests reached Meteor's real wallet screen through the cloud challenge flow; this does not establish a completed wallet approval. Physical-device approval, signed return and two-device synchronization remain acceptance checks.

To intentionally retain build 2-style local identity, leave both API settings empty. The public music source still works, Meteor profiles remain on the device, and no cloud session is created. Do not use that configuration when testing cross-device synchronization.

The ignored `ios/Config/Local.xcconfig` can contain `DEVELOPMENT_TEAM = YOUR_TEAM_ID` and intentional local overrides. Never commit signing secrets or wallet credentials.

## Optional owned-backend mode

The separate legacy Rust mode uses `MOBILE_API_BASE_URL` and leaves `CLOUD_API_BASE_URL` empty. It selects that server's catalog instead of the public adapter. Deploy the Rust backend with `MOBILE_ONLY=true`, a separate migrated database, and the [mobile API configuration and moderation instructions](../docs/mobile-api.md). Its catalog remains empty until an operator approves tracks. This mode supplies private versioned libraries, server report storage, revocable sessions, and independent Apple/Meteor accounts; it is not the default build 3 deployment.

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
