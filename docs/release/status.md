# Dacha FM release readiness — 26 September 2026

This is a development implementation, not an approved App Store release. The user authorized autonomous implementation and upload; no further design approval is pending.

## Delivered code

- Fork: https://github.com/whendacha/dacha-fm (upstream `fastnear/near-fm`, inspected commit `7aa4bad`).
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
- Under the initial development name, upload was attempted through Xcode automatic distribution as **internal TestFlight only**. Apple rejected the app-record lookup: `IDEDistribution.DistributionAppRecordProviderError.missingApp(bundleId: "com.whendacha.nearfm")`; the command reported `Error Downloading App Information`. **No build was uploaded, no TestFlight receipt was received, and no App Review submission was made.**

## Remaining release dependencies

1. Owned HTTPS API/bridge and actual privacy/support pages are not configured. Release currently displays service unavailability; it must not be submitted for App Review as a functional production service.
2. Real catalog access and rights to distribute the upstream code and audio are unconfirmed. The product uses its own Dacha FM branding; no upstream brand license is assumed. Upstream has no explicit license at the inspected revision; GitHub fork visibility does not establish App Store distribution rights.
3. Real Meteor signing/popup/return and Apple login/revocation need end-to-end verification against deployed services on a physical iPhone. UI/provider success is never fabricated. A paired phone was detected, but those live flows were not executed.
4. Moderation storage and an operator SQL workflow exist; a responsible operator, response policy and ongoing moderation are not supplied by code.
5. The user completed App Store Connect login. App record **6816319440** was created and renamed **Dacha FM**. The app uses bundle ID `com.whendacha.dachafm`, and Apple accepted its first build on 26 September 2026 at 07:24:38 MSK (04:24:38 UTC); current upload outcome is recorded below. Apple displays an updated Developer Program agreement notice requiring account-holder acceptance for submission. Current privacy declarations, age rating, review access and final metadata also remain necessary.

Apple approval is decided by App Review. The relevant requirements include [user-generated content, minimum functionality, login, privacy and intellectual property](https://developer.apple.com/app-store/review/guidelines/) and [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/). No guarantee of approval is made.

## Intentional scope limits

The first version is a free listener, without generation, upload, payments, crypto transfers, offline audio downloads or automatically created custody wallets. Apple and Meteor are separate accounts; account linking and session refresh are not implemented. Expired sessions require login. Library conflicts require an explicit in-app choice. Local metadata remains editable offline; audio needs a valid accessible stream. No production database or media was copied from Near.fm.

## Local artifacts

The earlier development archive and IPA are retained locally for evidence. The signed Dacha FM archive and export are `ios/build/DachaFM.xcarchive` and `ios/build/DachaFM-AppStore/DachaFM.ipa`. Archive, export, strict codesign verification and IPA integrity validation passed. The renamed app also passed its simulator UI test (1 test, 0 failures; `/tmp/DachaFM-UITests.xcresult`). These are ignored build outputs; no private signing keys or raw authentication logs are committed. Version is 1.0.0, build 1. A locally exported IPA is not evidence of a successful upload.

## Dacha FM rename and current upload

The user expressly selected Dacha FM and prohibited using the upstream name as this product brand. Visible native/bridge branding, App Store name, executable, bundle identifier and callback scheme now use Dacha FM / `com.whendacha.dachafm` / `dachafm`. Technical source type/file names and original provenance remain where needed for code compatibility and attribution. The owned fork is now `whendacha/dacha-fm`. A normal App Store Connect build, without the internal-only TestFlight restriction, was uploaded successfully. At 07:24:38 MSK (04:24:38 UTC) Xcode reported `Uploaded package is processing.` followed by `Upload succeeded.` and `EXPORT SUCCEEDED`. The local log is `ios/build/dachafm-apple-upload.log`, and a sanitized build record is `ios/build/dachafm-build-evidence.json`. The uploader still prints the internal Xcode scheme name `NearFM`; the actual package is `DachaFM.ipa`, bundle `com.whendacha.dachafm`, version **1.0.0 (1)**. **Apple has received the build; no App Review submission or approval has occurred.**

## TestFlight verification

App Store Connect subsequently showed upload **Completed** and build **1.0.0 (1)** ready for testing. The build was added to a private internal testing group and the account owner was invited at the user's explicit request. No public TestFlight link or external beta review was requested, and no App Review submission was made. The actual Release build still requires production API, bridge and catalog configuration; this limitation was disclosed to the user before invitation. The user states that the catalog is AI-generated; that statement is not a license for upstream source code and no rights declaration was submitted to Apple.
