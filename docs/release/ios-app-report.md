# iOS listener implementation report

Date: 2026-09-26

## Implemented

- Native iOS 17 SwiftUI listener with Russian dark music UI, artist catalog/search, paginated author pages, favorites, editable playlists, settings, reporting, blocking, mini player and full player.
- `AVPlayer` playback with strict author queues, explicit mixed-author playlist queues, background audio category, Now Playing metadata, remote commands, seek, shuffle/repeat, interruption and headphone removal handling. Queue and position restore paused. A blocked artist is removed immediately.
- Guest library stored on disk. Signed-in libraries use separate files keyed by a hash of user ID; restored playback is tagged by account ID. Guest merge is an explicit action. Sync uses optimistic versioning, preserves pending local edits, and presents a choice on 409 conflict. Account deletion clears the local account only after server confirmation.
- Guest mode and the pending guest merge share the same in-memory store instance, so guest edits remain current across sign-in and logout. At an author page boundary, playback fetches remaining pages before repeat can wrap to the first song.
- Asynchronous library responses are bound to a specific account session generation; delayed conflict fetches cannot populate a later login, including a relogin to the same user ID. Author-page responses only advance playback while the matching user intent remains active. Pausing, seeking, going back, shuffle, interruptions and headphone removal invalidate it. Playback position is checkpointed about every five seconds and when the app enters the background.
- If a listener asks for Next again while the same author page is loading, the in-flight response serves the latest intent. A failed song at a page boundary continues into later author pages when available; it never triggers a repeat loop over failed songs.
- Apple authorization uses the system Sign in with Apple button, a random nonce and lowercase SHA256 nonce hash sent to Apple; raw nonce, identity token and authorization code go to the mobile API. Meteor uses a random PKCE verifier/state through `ASWebAuthenticationSession`, validates `dachafm://auth/callback` and exchanges a one-time code. Session token stays in Keychain.
- Live networking requires `MobileAPIBaseURL` in Info.plist. `MeteorBridgeURL` is the HTTPS **origin**; the client appends `/mobile/auth`. `PrivacyPolicyURL` and `SupportURL` are optional, but required for a release with working links. HTTP is accepted only for DEBUG localhost. Missing configuration produces an unavailable state. DEBUG `--demo` uses a bundled `demo.wav` and labels it as demo; `--ui-test-store <UUID>` isolates UI-test storage.

## Verification

- `xcodebuild -quiet -project ios/NearFM.xcodeproj -scheme NearFM -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` passed after the final UI, playback and sync edits.
- `swift test --package-path ios/Packages/NearFMCore` passed: 11 tests, including delayed playback-page intent and author page-boundary regressions, mixed playlist queue, library persistence and wire format.
- Root owns simulator launch/screenshots and full integration checks. This report does not claim a live backend, Apple login, Meteor wallet signature, physical-device background playback or App Store upload verification.

## Live integration and release needs

- Set real HTTPS mobile API and Meteor bridge origins, deploy the backend and web bridge, and test both sign-in methods end to end. The Meteor browser/wallet callback remains unverified on a physical iPhone.
- Verify catalog licensing, code/brand rights, moderation operation, privacy/support URLs, Apple developer signing and App Store Connect access before distribution.
- Test account switching, 409 resolution, server-side deletion and reporting against a live PostgreSQL-backed service; simulator demo mode cannot establish these behaviors.
