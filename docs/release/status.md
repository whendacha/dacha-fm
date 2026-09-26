# Release readiness — 26 September 2026

This is a development implementation, not an approved App Store release. The user authorized autonomous implementation and upload; no further design approval is pending.

## Delivered code

- Fork: https://github.com/whendacha/near-fm (upstream `fastnear/near-fm`, inspected commit `7aa4bad`).
- Native SwiftUI iPhone listener, strict author queues with pagination, persistent guest favorites and playlists, AVPlayer/Now Playing, optional Meteor and Apple identities, private versioned library sync, report/block/account deletion flows.
- Separate Rust mobile API and PostgreSQL schema, explicit human catalog approval, revocable sessions, NEP-413/PKCE, Apple validation and token revocation.
- Meteor HTTPS bridge with direct identity signing, user-activated popup, fixed callback and cancellation invalidation.
- Reproducible Xcode project, original icon/demo tone, core and simulator UI tests, service configuration instructions in `ios/README.md` and `docs/mobile-api.md`.

## Evidence

- Native core: 11 tests passed after the account/playback review fixes. See `core-report.md` and `ios-app-report.md` for scope.
- Rust backend: 10 tests passed with disposable PostgreSQL; local HTTP tests also verified owner isolation, conflicts, moderation, deletion/revocation and one-use code exchange races. See `backend-report.md` and `backend-test-results.txt`.
- Meteor bridge: 3 protocol tests, TypeScript and Next.js production build passed. Independent re-review confirmed the popup/cancellation fixes. See `bridge-report.md`.
- iPhone simulator build and launch succeeded. The development screenshot in `screenshots/iphone-listen.png` shows the explicitly labeled demo and original tone, not a real music catalog.
- A device Release archive and local App Store `.ipa` export succeeded using automatic signing. This is evidence of packaging/signing, not Apple receipt or review approval.
- Final simulator UI test passed: favorite and playlist persistence across relaunch, author screen and playback. The first two UI runs exposed ambiguous test locators, corrected with a stable author accessibility identifier; the final run passed (1 test, 0 failures).
- Final core rerun passed: 11 tests, 0 failures. Final device Release archive succeeded after all reviewed fixes.
- Upload attempted through Xcode automatic distribution as **internal TestFlight only**. Apple rejected the app-record lookup: `IDEDistribution.DistributionAppRecordProviderError.missingApp(bundleId: "com.whendacha.nearfm")`; the command reported `Error Downloading App Information`. **No build was uploaded, no TestFlight receipt was received, and no App Review submission was made.**

## Remaining release dependencies

1. Owned HTTPS API/bridge and actual privacy/support pages are not configured. Release currently displays service unavailability; it must not be submitted for App Review as a functional production service.
2. Real catalog access and rights to distribute the upstream code, Near.fm brand and audio are unconfirmed. Upstream has no explicit license at the inspected revision; GitHub fork visibility does not establish App Store distribution rights.
3. Real Meteor signing/popup/return and Apple login/revocation need end-to-end verification against deployed services on a physical iPhone. UI/provider success is never fabricated. A paired phone was detected, but those live flows were not executed.
4. Moderation storage and an operator SQL workflow exist; a responsible operator, response policy and ongoing moderation are not supplied by code.
5. An App Store Connect app record for `com.whendacha.nearfm` is absent, as confirmed by the upload attempt. Creating that record requires access to the appropriate App Store Connect account. Current privacy declarations and age rating, review access and final metadata also remain necessary. Browser App Store Connect showed the login page; Xcode automatic signing/export nevertheless succeeded. Missing browser login alone is not evidence that upload is impossible.

Apple approval is decided by App Review. The relevant requirements include [user-generated content, minimum functionality, login, privacy and intellectual property](https://developer.apple.com/app-store/review/guidelines/) and [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/). No guarantee of approval is made.

## Intentional scope limits

The first version is a free listener, without generation, upload, payments, crypto transfers, offline audio downloads or automatically created custody wallets. Apple and Meteor are separate accounts; account linking and session refresh are not implemented. Expired sessions require login. Library conflicts require an explicit in-app choice. Local metadata remains editable offline; audio needs a valid accessible stream. No production database or media was copied from Near.fm.

## Local artifacts

Final signed archive: `ios/build/NearFM.xcarchive`. App Store export: `ios/build/AppStore/NearFM.ipa`. These are ignored build outputs; no private signing keys or raw authentication logs are committed. Version is 1.0.0, build 1. A locally exported IPA is not evidence of a successful upload.
