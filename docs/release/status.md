# Dacha FM release status — 26 September 2026

Build **1.0.0 (1)** was uploaded, processed and made available to the invited internal TestFlight tester. It had no configured catalog or sign-in service. The user reported that music and authorization did not work. Build **1.0.0 (2)** addresses that configuration failure with direct public streaming and a separate local Meteor identity flow. Its three simulator UI tests and signed archive/export checks have passed. Apple received build 2 at **07:50:32 MSK (04:50:32 UTC) on 26 September 2026** and reported it processing. TestFlight readiness for build 2 has not yet been verified. No App Review submission or approval has occurred.

## Build 2 behavior

- The native SwiftUI app reads the public `https://api.near.fm/api/songs` catalog and streams the existing HTTPS audio URLs. No source database or audio collection is copied or rehosted. Public requests never carry a Dacha FM session token or private library.
- Favorites, editable playlists and blocked authors persist on the iPhone. Guest and verified-wallet libraries use separate files. Guest merging is an explicit action; cloud synchronization is disabled in this mode.
- Author queues filter by exact uploader ID. Public catalog requests use source pagination, with up to 100 records per page and a bounded scan of three pages per call. Author discovery is incremental; searching song text is separate from matching author names and exact profile slugs.
- `mobile-bridge/` builds a static Meteor page into `docs/mobile/auth/`, deployed under `https://whendacha.github.io/dacha-fm`. It asks only for a signature over the fixed identity statement and returns a proof to `dachafm://auth/callback` in a fragment. Deployment and the native browser's opening of Meteor have been verified; actual wallet approval and the signed return remain unverified.
- Native verification checks callback shape, state, nonce, recipient, Ed25519 signature and a five-minute lifetime. A fixed mainnet RPC must confirm that the signing key has FullAccess ownership of the claimed account. No transaction, contract permission, seed phrase or private key is requested.
- The verified account ID is stored in Keychain for the local library. This flow creates no upstream account, bearer token or cloud session. Sign in with Apple is not enabled in public-catalog mode.
- Blocking is local and immediate. Public-mode reporting directs listeners to the source or support instead of claiming delivery to an unconfigured moderation backend. Privacy and support documents describe this mode.

## Current verification evidence

- `swift test --package-path ios/Packages/NearFMCore` passed on 26 September 2026 at 07:46 MSK: **19 tests, 0 failures**. This includes public-catalog mapping/filtering and native wallet-proof validation in addition to queue/library tests.
- A native Swift URLSession smoke test fetched 100 live tracks and 12 authors. An author-only request returned 10 tracks, all with uploader ID `32`.
- An observed public HTTPS MP3 responded to HEAD with `200`, `audio/mpeg` and byte-range support. A bounded 1,024-byte range request returned `206`; no full audio file was downloaded for that check.
- All **three iOS simulator UI tests passed at 07:48:48 MSK**, recorded in `/tmp/DachaFM-Build2-UITests.xcresult`: guest-library persistence and author playback; live audio for “Beautiful India” by `tinsman.near`, with elapsed playback progressing to `0:05`; and the actual `ASWebAuthenticationSession` bridge Prepare/Confirm flow opening `wallet.meteorwallet.app` and its clean-wallet “Get Started” screen.
- `python3 ios/scripts/preflight_public_release.py --json` passed against the deployed services: bridge HTML/assets and privacy/support pages returned HTTP 200, the deployed bridge JavaScript exactly matched local SHA-256 `9a3a110692b88cda42f1c378d9003260efd07f90de9814e7d0ca81b8dee9a2fa`, the catalog returned 100 playable songs, and the checked audio URL returned HEAD 200.
- Bridge protocol checks passed **seven tests, zero failures**. The new catalog adapter and existing MobileAPI also passed a Swift typecheck.
- The signed Release archive and export for **1.0.0 (2)** passed. IPA ZIP integrity and strict code-signature validation passed. Local artifacts are `ios/build/DachaFM-Build2.xcarchive`, `ios/build/DachaFM-Build2-AppStore/DachaFM.ipa`, and `ios/build/dachafm-build2-evidence.json`; IPA SHA-256 is `d4bb34cb9bc4550b7e4d107f9d1a2f8380772c35fe1c48a96670aed67306db0e`.
- The wallet UI test stops at the clean-wallet entry screen. Native cryptographic tests use controlled signatures and independent payload construction. Neither establishes actual wallet approval or the signed return on a physical iPhone.
- The actual build 2 upload log, `ios/build/dachafm-build2-upload.log`, records `Uploaded package is processing.` at 07:50:32.674 MSK, `Upload succeeded.` at **07:50:32.676 MSK**, and `EXPORT SUCCEEDED`. This confirms receipt of **1.0.0 (2)**; TestFlight processing/readiness remains to be verified.

See [core-report.md](core-report.md), [ios-app-report.md](ios-app-report.md), and [bridge-report.md](bridge-report.md) for scope. Earlier backend verification remains in [backend-report.md](backend-report.md) and [backend-test-results.txt](backend-test-results.txt).

## Optional owned-backend implementation

The repository also contains an isolated Rust mobile API, PostgreSQL schema and Next.js authentication bridge. When intentionally configured and deployed, that separate mode supports Apple/Meteor server identities, revocable sessions, a human-approved catalog, private versioned library synchronization and server report storage. Those services are not used by default build 2. Their earlier checks passed 10 backend tests with disposable PostgreSQL plus local HTTP isolation/conflict/deletion/code-exchange checks. The server bridge passed three protocol tests, TypeScript and its Next.js build. These are implementation checks, not evidence of deployed production services.

## Build 1 upload and TestFlight record

The owned fork is [whendacha/dacha-fm](https://github.com/whendacha/dacha-fm), based on upstream `fastnear/near-fm` commit `7aa4bad`. The user chose Dacha FM and prohibited use of the upstream name as this product's brand. App Store name, executable, bundle ID and callback scheme use Dacha FM / `DachaFM.app` / `com.whendacha.dachafm` / `dachafm`. Internal source/scheme names remain where needed for compatibility and attribution.

An early attempt under the initial development name failed with `IDEDistribution.DistributionAppRecordProviderError.missingApp`; no package was delivered by that attempt. After user login and creation of App Store record **6816319440**, a normal App Store Connect upload succeeded at **07:24:38 MSK (04:24:38 UTC)** on 26 September 2026. Xcode reported `Uploaded package is processing.`, `Upload succeeded.` and `EXPORT SUCCEEDED` for **1.0.0 (1)**.

App Store Connect subsequently showed the upload **Completed** and build **1.0.0 (1)** ready for testing. It was added to a private internal group and the account owner was invited at the user's request. This was not an external beta review or App Review submission. The absence of configured services in that build was disclosed; the user's ensuing failed test prompted build 2.

Build 1 artifacts are local ignored outputs: `ios/build/DachaFM.xcarchive`, `ios/build/DachaFM-AppStore/DachaFM.ipa`, `ios/build/dachafm-apple-upload.log`, and `ios/build/dachafm-build-evidence.json`. The renamed build 1 simulator UI test passed at `/tmp/DachaFM-UITests.xcresult`. Do not treat an old artifact or a successful archive as a build 2 upload receipt. No private keys or raw authentication logs are committed.

## Remaining release checks

1. Complete actual Meteor approval and the signed return on a physical iPhone, along with separate guest/wallet library behavior. The deployed bridge and Meteor entry screen have been verified; no real-wallet approval is claimed yet.
2. Verify completed Apple processing and TestFlight availability of **1.0.0 (2)**. The upload receipt, simulator tests and signed packaging have passed; physical-device checks of background audio, interruptions, headphone removal and author-page boundaries remain separate.
3. For App Review, complete current privacy disclosures, age rating, review access, metadata, moderation/support responsibilities and any Apple account-holder agreement requirements. The previously observed Developer Program agreement banner is not evidence that its updated terms have been accepted.
4. Confirm the source/content permissions required for public distribution. The inspected upstream repository has no explicit license. The user identifies the catalog as AI-generated; this document does not assert that AI generation or public HTTP accessibility grants distribution rights, and no rights declaration has been submitted to Apple.

The app remains a free listener without generation, uploads, payments, cryptocurrency transfers or offline audio downloads. Apple decides App Review outcomes; no approval guarantee is made. Reference requirements: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
