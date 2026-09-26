# iOS listener implementation report

Date: 2026-09-26. Current source targets Dacha FM **1.0.0 (2)**. Its simulator UI tests and signed packaging have passed. Apple received it at **07:50:32 MSK (04:50:32 UTC)** and reported it processing; TestFlight readiness remains unverified. Build 1 was previously delivered through TestFlight.

## Current listener mode

The native iOS 17 SwiftUI application provides artist discovery, author-only queues, favorites, editable playlists, blocking, guest listening, a mini player and full player. With `MOBILE_API_BASE_URL` empty, a dedicated credential-free adapter reads the live public catalog and streams the existing HTTPS audio URLs. It does not require the separate Rust API for listening.

Public song mapping uses the song UUID and stable numeric uploader ID. Records marked hidden, deleted or unvalidated, and records without a usable HTTPS audio URL, are excluded. Author requests filter exact IDs while scanning bounded source pages; page cursors and `hasMore` use the raw source response. Discovery remains incremental. Public-mode reporting opens the source/support path instead of claiming that an absent backend received a report.

`AVPlayer` handles author queues and explicit mixed-author playlists, background audio, Now Playing/remote commands, seek, shuffle/repeat, interruptions and headphone removal. Position checkpoints are written approximately every five seconds and on background entry; restoration starts paused. Blocking removes an author from the queue. At an author-page boundary, further pages are fetched before repeat wraps; late responses only advance playback while the matching intent remains active.

Libraries are local in this mode. Guest and wallet libraries use separate files; an explicit action merges the guest library. Account changes clear playback and invalidate account-dependent work. There is no cloud synchronization or Sign in with Apple in the default public-catalog configuration.

Meteor opens the static HTTPS bridge through `ASWebAuthenticationSession`. The bridge signs the fixed identity statement without calling wallet `signIn`, requesting contract access or initiating a transaction. The native verifier checks the original nonce, state, recipient, Ed25519 signature, callback shape and five-minute expiry, then verifies mainnet FullAccess-key ownership through the fixed RPC endpoint. Only the verified account ID is accepted for the on-device library; no upstream or Dacha server account is created. Keychain stores the local identity. Logout returns to guest mode; deletion concerns the local Dacha profile/library, not the wallet or blockchain.

## Configuration

The native app's bridge base defaults to `https://whendacha.github.io/dacha-fm`; it appends `/mobile/auth`. Static bridge sources are in `mobile-bridge/`, generated output in `docs/mobile/auth/`, with `docs/privacy.html` and `docs/support.html`. Release preflight verified these deployed HTTPS pages/assets, including an exact match between local and served bridge JavaScript.

Debug `--demo` uses a labeled, original bundled tone, and `--ui-test-store <UUID>` isolates test storage. Normal Release behavior uses the public catalog rather than the demo.

The optional owned-backend mode remains implemented and is selected by a nonempty `MobileAPIBaseURL`. It requires its own Rust API and server/PKCE Next.js bridge, plus configured Apple credentials to enable Apple sign-in. That mode provides server accounts, cloud libraries/conflict handling and report storage. Its service setup is separate from the static local-identity bridge; see [the iOS README](../../ios/README.md).

## Verification and limits

- Shared core tests passed on 26 September 2026 at 07:46 MSK: **19 tests, 0 failures**, including public schema and native signature/RPC response validation.
- Native Swift URLSession smoke testing fetched 100 live tracks, 12 authors, and an author-only response of 10 tracks all matching uploader ID 32.
- The public adapter and existing MobileAPI passed a Swift typecheck. A public audio endpoint passed HEAD and bounded byte-range checks; this is not evidence that every source track plays successfully.
- All **three build 2 iOS simulator UI tests passed at 07:48:48 MSK**, in `/tmp/DachaFM-Build2-UITests.xcresult`. They cover persistent guest favorites/playlists and author playback, live streaming, and the native browser's bridge-to-Meteor entry flow.
- Live playback of “Beautiful India” by `tinsman.near` progressed to `0:05`. The real `ASWebAuthenticationSession` Prepare/Confirm flow opened `wallet.meteorwallet.app` and the clean-wallet “Get Started” screen. No wallet was created, imported or used to approve a signature in that test.
- `python3 ios/scripts/preflight_public_release.py --json` passed: deployed bridge/assets and privacy/support pages returned HTTP 200, bridge JavaScript matched SHA-256 `9a3a110692b88cda42f1c378d9003260efd07f90de9814e7d0ca81b8dee9a2fa`, the first catalog page contained 100 playable songs, and the audio HEAD probe returned 200.
- Signed Release archive/export for **1.0.0 (2)** passed, as did IPA ZIP integrity and strict code-signature checks. The IPA at `ios/build/DachaFM-Build2-AppStore/DachaFM.ipa` has SHA-256 `d4bb34cb9bc4550b7e4d107f9d1a2f8380772c35fe1c48a96670aed67306db0e`. Sanitized evidence is in `ios/build/dachafm-build2-evidence.json`.
- Apple upload succeeded at **07:50:32.676 MSK**, confirmed by `ios/build/dachafm-build2-upload.log`, which also reports the uploaded package processing and `EXPORT SUCCEEDED`. TestFlight readiness remains unverified. Actual Meteor approval and the signed return on a physical iPhone remain unverified, as do physical-device background/route-interruption checks. Reaching the Meteor entry screen and verifying controlled signatures do not substitute for real wallet approval.
