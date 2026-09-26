# Dacha FM for iPhone

Native SwiftUI listener for iOS 17+, developed in the [whendacha fork](https://github.com/whendacha/dacha-fm). Features include author-only queues, playlists, favorites, a persistent guest library, AVPlayer/lock-screen controls, optional Meteor or Apple login, account-scoped synchronization, reporting, blocking, and account deletion.

This repository contains an implementation and development builds. It is **not an App Store submission**. Live provider/device verification, a production catalog/backend, distribution rights and signing remain release requirements; see [release status](../docs/release/status.md).

## Build and test

Open `NearFM.xcodeproj` in Xcode. The shared scheme is `NearFM`; the only Swift package is the local `Packages/NearFMCore`.

From the repository root:

```sh
swift test --package-path ios/Packages/NearFMCore
python3 ios/scripts/generate_project.py
xcodebuild -project ios/NearFM.xcodeproj -scheme NearFM \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/DerivedData CODE_SIGNING_ALLOWED=NO build
```

For UI tests, use an available simulator from `xcrun simctl list devices available`:

```sh
xcodebuild -project ios/NearFM.xcodeproj -scheme NearFM \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ios/DerivedData CODE_SIGNING_ALLOWED=NO test
```

The UI test opts into `--demo` and a unique `--ui-test-store` directory. Demo mode exists only in Debug, is visibly labeled, and uses a bundled original synthesized tone. It does not simulate successful login, sync or report submission. Release builds require the real API. To inspect the demo manually, add `--demo` in the scheme's Run arguments. Account sessions are stored in Keychain; library files are separate per account and guest.

`scripts/generate_project.py` deterministically recreates the project and shared scheme after adding Swift/resource files. `scripts/generate_resources.swift` recreates the original icon/tone. Keep app configuration in xcconfig files so regeneration preserves it.

## Service configuration

Create the ignored `ios/Config/Local.xcconfig`:

```xcconfig
// Replace these examples with owned, deployed HTTPS services.
// $() prevents xcconfig from treating // as a comment.
MOBILE_API_BASE_URL = https:/$()/api.example.com
METEOR_BRIDGE_URL = https:/$()/music.example.com
PRIVACY_POLICY_URL = https:/$()/music.example.com/privacy
SUPPORT_URL = https:/$()/music.example.com/support
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

API and bridge settings are **origins**, without `/api/mobile/v1` or `/mobile/auth`; the app appends these paths. Empty settings display an unavailable state. The native API client permits HTTP localhost only in Debug.

Deploy the Rust backend with `MOBILE_ONLY=true` using [the configuration and moderation instructions](../docs/mobile-api.md). Use a separate database with migrations applied. The mobile catalog remains empty until an operator explicitly approves tracks whose distribution rights are verified.

For the Next.js bridge, configure server-side `MOBILE_API_URL` to the API origin and `MOBILE_NEAR_NETWORK=mainnet` or `testnet`. The route `/mobile/auth` performs NEP-413 signing through Meteor and returns a one-time PKCE code to the app. A physical iPhone test of Meteor's popup and return flow is still required.

Register `com.whendacha.dachafm` (or an owned replacement bundle ID) with Sign in with Apple in the intended Apple team. Configure the matching backend audience, Apple client secret and token-encryption key. Changing the bundle ID also requires updating the backend audience and project settings. The callback scheme is `dachafm`; it uses random state and PKCE. Apple and Meteor identities are independent accounts in this version; linking is not implemented. Sessions expire after 30 days and require another login.

## Archive and upload

With the production settings and a valid Apple Developer account configured:

```sh
xcodebuild -project ios/NearFM.xcodeproj -scheme NearFM \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath ios/build/DachaFM.xcarchive \
  -allowProvisioningUpdates archive
```

Validate and distribute the signed archive in Xcode Organizer to the matching App Store Connect record. A successful archive alone is not an upload; retain Apple's upload receipt and processed build number before reporting submission. Test guest listening, both login methods, sync conflicts, logout/deletion, interruptions, headphones and background playback on a physical device before submission. Complete the actual catalog's age rating, App Privacy disclosures, privacy/support pages, content permissions and review access. Demo assets/screenshots are development evidence and must not be presented as the production catalog.

The public upstream has no explicit license at the inspected commit `7aa4bad`. A GitHub fork does not establish rights to distribute the source, brand or music in the App Store. No license grant is asserted by this fork, and Apple approval cannot be guaranteed.
