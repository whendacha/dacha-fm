# iOS Listener Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. The user explicitly authorized autonomous implementation and Apple upload on 2026-09-26; do not ask for design approval again.

**Goal:** Deliver a fork with a native iPhone music listener, author-scoped queues, playlists, favorites, Meteor/Apple authentication and a verified build; upload only when signing, service configuration and distribution prerequisites are actually satisfied.

**Architecture:** SwiftUI app with an independently tested Foundation core package; AVFoundation playback; Rust/Axum mobile API with separate listener identities and private library. Existing web project hosts a Meteor authentication bridge. Deployment credentials and rights must not be invented.

**Tech Stack:** Swift 6 in Swift 5 language mode, iOS 17+, SwiftUI, AVFoundation, AuthenticationServices, Security/Keychain, Rust/Axum/PostgreSQL, existing Next.js web app.

## Global constraints

- Work in the existing `codex/ios-app` branch. Do not change upstream production or commit secrets.
- iOS 17 minimum. Native guest listening and persistent local library.
- Author-only queue must never fall through to the general radio.
- Favorites are private, free and distinct from public votes.
- Meteor confirms identity with a signature, never a seed phrase or transfer.
- Apple sign-in is a real alternative; no requirement to subsequently connect Meteor.
- Existing code and catalog have unconfirmed distribution rights; record this as a release blocker, not as a license grant.
- Independent file ownership permits parallel work; agents must not commit or change another agent's files. Root integrates and commits.
- No invented production URLs, signing teams, successful authentications or upload claims.

## Shared client/server contract

Base path `/api/mobile/v1`. JSON uses snake_case. Dates use ISO8601; library version uses integer optimistic concurrency.

```json
{"id":"song-uuid","title":"Title","artist_id":"123","artist_name":"Artist","audio_url":"https://example.org/audio.mp3","artwork_url":null,"duration":180.0}
```

`Artist`: `id`, `name`, `artwork_url` (optional), `track_count` (integer).

- `GET /tracks?q=&artist_id=&page=1&limit=30` -> `{tracks:[Track], page:1, has_more:true}`. Moderated, valid, visible records only.
- `GET /artists?q=&page=1&limit=30` -> `{artists:[Artist], page:1, has_more:false}`.
- `GET /library` authenticated -> `{version:0, favorites:[Track], playlists:[{id,name,tracks:[Track]}], blocked_artist_ids:[String]}`.
- `PUT /library` authenticated with exact snapshot above; compare version, validate tracks and ownership, increment version; conflict 409; return saved snapshot. Client must fetch/merge deliberately on conflict, never blindly overwrite another device.
- `POST /reports` -> `{track_id?:String,artist_id?:String,reason:String}`; authenticated or rate-limited anonymous, persist complaint; returns success only after insert.
- `POST /auth/apple` -> `{identity_token:String,nonce:String,authorization_code:String}` -> session.
- `POST /auth/meteor/challenge` -> `{code_challenge:String}` -> `{id:String,message:String,nonce:[UInt8],recipient:String,expires_at:String}`.
- `POST /auth/meteor/verify` -> `{challenge_id:String,account_id:String,public_key:String,signature:String}` -> `{code:String}`; server reconstructs stored challenge, validates NEP-413 with callback None, NEAR access-key ownership, consumes once.
- `POST /auth/exchange` -> `{code:String,code_verifier:String}` -> session.
- Session -> `{access_token:String,user_id:String}`. Server stores hash of revocable opaque token, expiry <=30 days. Keychain on iOS. Logout/account delete revoke.
- `POST /auth/logout`; `DELETE /account` authenticated.
- `GET /config` -> `{meteor_enabled:Bool,apple_enabled:Bool,privacy_url:String?,support_url:String?}`. Unconfigured integrations fail explicitly rather than faking success.

Meteor browser bridge URL `/mobile/auth?code_challenge=...&state=...`; fixed callback `nearfm://auth/callback?code=...&state=...`. App validates state and exchanges code using verifier. Bridge does not send bearer session in URL. Own HTTPS deployment required. No claimed native-app deep-link support from Meteor until proven.

## Task 1 — Core library and behavioral tests

Files owned: `ios/Packages/NearFMCore/**`. Create a Swift package exposing the following public types with explicit public initializers:

```swift
struct Track: Codable, Equatable, Identifiable, Sendable {
  let id: String; let title: String; let artistID: String; let artistName: String
  let audioURL: URL; let artworkURL: URL?; let duration: Double?
}
struct Artist: Codable, Equatable, Identifiable, Sendable {
  let id: String; let name: String; let artworkURL: URL?; let trackCount: Int
}
struct Playlist: Codable, Equatable, Identifiable, Sendable {
  let id: String; var name: String; var tracks: [Track]
}
struct LibrarySnapshot: Codable, Equatable, Sendable {
  var version: Int; var favorites: [Track]; var playlists: [Playlist]
  var blockedArtistIDs: [String]
}
```

`PlaybackQueue` is a value type with `tracks`, `index`, `artistID`, `current`, `replace(with:artistID:startID:)`, `append(_:)`, `next(repeatAll:)`, `previous()`, `removeArtist(_:)`, `shuffle()`; mutators return Void except next/previous Bool. Index is Int, empty = 0. Reject other-author tracks on replacement/appending. Deduplicate by id. Expose initializer `init()`.

`LibraryStore` is a `@MainActor` class with `snapshot`, `init(fileURL: URL) throws`, `toggleFavorite(_:) throws`, `createPlaylist(name:) throws -> String`, `renamePlaylist(id:name:) throws`, `deletePlaylist(id:) throws`, `add(_:to:) throws`, `remove(trackID:from:) throws`, `moveTrack(in:from:to:) throws`, `blockArtist(_:) throws`, `unblockArtist(_:) throws`, `replace(_:) throws`, `mergeGuest(_:) throws`. Atomic JSON persistence; load errors must not destroy stored data. Validate playlist names; preserve order; block removes content from all library lists.

- [ ] Write queue tests covering artist-only next/append/shuffle, duplicates, empty/end queues and removal of current author; observe failure.
- [ ] Implement queue and run `swift test --package-path ios/Packages/NearFMCore`.
- [ ] Write persistence tests: reopen library, playlist edits/reorder, duplicate favorites/tracks, blocking, guest merge and corrupt file handling; observe failure then implement.
- [ ] Verify real snake_case JSON decoding and exact wire output.

## Task 2 — Native UI and playback

Files owned: `ios/NearFM/App/**`, `ios/NearFM/Playback/**`, `ios/NearFM/Services/**`, `ios/NearFM/Views/**`. Root owns Xcode project, resources, Info.plist, entitlements and tests outside the package.

- [ ] Implement `@main struct NearFMApp: App` and `@MainActor @Observable AppModel` for guest library, catalog pagination, artist search, playback, account and error state. Use core contract above.
- [ ] `MobileAPI` uses URLSession, strict HTTPS except DEBUG localhost, explicit request errors and session bearer. No production base URL guessed. Read `MobileAPIBaseURL`, `MeteorBridgeURL`, `PrivacyPolicyURL`, `SupportURL` from Info.plist; missing config gets an honest setup/unavailable state. In DEBUG, support explicit `--demo` with local bundled fixture tracks; never silently replace live data with fake success.
- [ ] `AudioPlayer` wraps AVPlayer/AVQueuePlayer, maintains core queue, remote commands, Now Playing, seek, repeat/shuffle, interruption/headphone handling, load-more author queue. Controls reflect AVPlayer state and errors. Restore paused queue/position.
- [ ] Build polished accessible SwiftUI screens: Listen hero/search and artists; author songs and play-only-author; library favorites/playlists; create/rename/reorder/edit actions; full player + mini player; settings login, logout, deletion, report/block/support/privacy.
- [ ] Authentication: real Apple authorization flow with hashed nonce and backend identity token verification; Meteor ASWebAuthenticationSession with random PKCE verifier/state, SHA256 challenge, callback state validation and exchange; Keychain token. Browser result cancellation and unconfigured server must remain distinguishable from success.
- [ ] UI reflects local vs synced status. Account changes use separate library file per user and guest; do not leak previous account. Merge explicitly as an in-app user decision. Handle 409 without automatic destructive upload. Deletion only clears local account after server acknowledges.
- [ ] Tests: SwiftUI compilation plus simulator launch; root handles screenshots and full integration build.

## Task 3 — Mobile backend

Files owned: `server/src/mobile/**`, `server/migrations/043_mobile_listener.sql` (choose next unused number if 043 already used), `server/src/main.rs` only module declaration and router merge, backend dependency adjustments if needed, `docs/mobile-api.md`.

- [ ] Add separate mobile identities/sessions/challenges/codes/library/reports tables. Use stable unique provider identity and one-time atomic challenge consumption. Listener Apple/Meteor auth never creates custody wallets. Guest library is local only.
- [ ] Implement shared endpoints exactly. Use existing moderated catalog joined to users; independent explicit content approval gate; do not equate technical audio validation to moderation. Check SQL parameterization, pagination cap, block filters, library size limits, one-time codes, PKCE, account session revocation and owner scope.
- [ ] Apple validation: verify JWKS signature/issuer/audience/expiry/nonce; authorization code exchange when configured to obtain revocable token; account deletion must revoke before deletion and report external failure honestly. Config via MOBILE_* env variables, reject disabled configuration with 503. Do not commit credentials. Meteor config own domain and recipient required.
- [ ] NEP-413: exact 32-byte server nonce, stored message, callback None, verify signature and NEAR key ownership, atomic consumption; no client-supplied message/recipient trust.
- [ ] Add focused unit tests first for pagination/name/size/input validation, PKCE, challenge expiry, NEP-413 proof. Include DB integration tests gated by TEST_DATABASE_URL; root will attempt PostgreSQL availability.
- [ ] Run cargo tests/check if toolchain available. Avoid unrelated formatting across upstream.

## Task 4 — Root integration, bridge and release

Files: `web/src/app/mobile/auth/**`, `ios/NearFM.xcodeproj/**`, `ios/NearFM/Resources/**`, `ios/NearFM/Info.plist`, `ios/NearFM/NearFM.entitlements`, `ios/Config/**`, `ios/scripts/**`, `ios/README.md`, `docs/release/**`.

- [ ] Create remote fork via authenticated GitHub UI and verify fork parent; set origin to user fork.
- [ ] Build Xcode project with local core package and iOS 17 target, Background Audio, Sign in with Apple entitlement, callback URL scheme, privacy manifest with accurate API declarations, valid app icon. Keep signing team configurable.
- [ ] Create Meteor web bridge implementing challenge/sign/verify/callback contract; state input validation and explicit cancel/error UI. Do not create login success on mere wallet address selection.
- [ ] Test native package, compile simulator/device archive as feasible, launch demo on simulator and inspect screenshots for layout. Verify actual API responses separately; demo is never a release substitute.
- [ ] Review backend auth/library boundaries and changed branch; fix actionable findings and rerun covering tests.
- [ ] Inspect signing identities, available App Store Connect session and project-scoped upload credentials without printing secrets. Build and upload only with real signing and permitted release content; store command output and App Store build acknowledgement as evidence.
- [ ] Write concrete release readiness record distinguishing code complete, simulator checks, live integration, signing and upload. If unavailable access/rights prevents upload, leave reproducible build instructions and report exact blockers without claiming submission.

## Progress

- Remote fork created; native app/core, mobile backend and Meteor bridge implemented.
- Independent reviews identified account isolation, queue pagination and popup/cancellation issues; corrections and final verification are recorded in `docs/release/status.md`.
- Database integration and HTTP contract checks passed. Live identity providers, production deployment and Apple upload remain separate verification steps.
- Historical task checkboxes above describe the intended workflow, including red-test steps that were not all executed. They must not be read as a completed test report. User approval supersedes earlier design gates.
