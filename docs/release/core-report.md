# Native core verification

The independent Swift package is at `ios/Packages/NearFMCore`. Its public models cover Track, Artist, Playlist and LibrarySnapshot; PlaybackQueue enforces author identity, and LibraryStore persists isolated libraries. Build 2 adds the public catalog parser and native Meteor identity challenge/proof verification.

On **26 September 2026 at 07:46 MSK**, `swift test --package-path ios/Packages/NearFMCore` completed with **19 tests and 0 failures**, using the local macOS Swift 6.3.3 toolchain:

- Five playback-queue tests cover author-only progression, append filtering, shuffle, duplicates, empty/end behavior, author page boundaries and explicit mixed-author playlists.
- One playback-intent test prevents a delayed author page from advancing after the listener changes intent.
- Four library tests cover persistence/order, favorites, blocking, guest merge, corrupt-file preservation, playlist validation and version preservation.
- One wire-format test covers the optional mobile API's snake_case models.
- Three public-catalog tests cover live schema mapping, stable numeric uploader identity, hidden/deleted/unvalidated records, missing or unsafe audio URLs, and pagination based on the unfiltered source count.
- Five wallet tests cover an independently constructed NEP-413 signature payload, nonce/message/recipient binding, callback state/expiry/duplicate rejection, malformed proofs and HTTPS constraints, and rejection of RPC errors or non-FullAccess keys.

Separately, all three build 2 iOS simulator UI tests passed at **07:48:48 MSK**, recorded in `/tmp/DachaFM-Build2-UITests.xcresult`: guest persistence/author playback, live audio progressing to `0:05`, and the actual authentication browser reaching Meteor's clean-wallet entry screen. Release preflight and signed archive/export checks also passed; see [status.md](status.md) for artifact hashes and scope.

These checks do not establish actual Meteor approval, the signed return on a physical iPhone or App Review approval. Separate release evidence confirms Apple received **1.0.0 (2)** at **07:50:32 MSK**, completed processing, and made it available in the existing internal TestFlight group with one tester. Optional server-mode mutations retain the server snapshot version so HTTP 409 conflicts can be resolved explicitly. Guest merges retain the destination account's blocked-author choices.
