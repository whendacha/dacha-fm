# Dacha FM App Review readiness

Status as of 26 September 2026: **APP REVIEW NOT SUBMITTED.** Dacha FM **1.0.0 (4)** remains in the existing internal TestFlight group. The App Store draft is populated; the privacy declaration is not published. No approval is guaranteed.

## Prepared App Store draft

- Build 4 is selected. English is the primary language; description, support URL and review notes are populated. The empty Russian version localization was removed, matching the English-interface requirement.
- Three actual app screenshots, each 1320 × 2868 pixels, are uploaded to the English 6.9-inch slot: player, library and artist. The player is first. Native capture evidence is in `ios/build/AppStore-Build4-Screenshots/capture-evidence.json`.
- Review contact fields are saved and were visually checked. The user-provided email is also published for support and content reports. Core guest use does not require sign-in; optional cloud access is explained in review notes.
- Six privacy categories are configured as linked, App Functionality and no tracking. Product Interaction additionally uses Product Personalization. Publication remains pending the external-retention questions in `docs/release/app-privacy-audit.md`.
- Deployed privacy/support pages were retrieved with curl and match the local bytes.
- A $0.00 base price and equivalent free prices are configured. Mac and Vision Pro distribution were disabled for this iPhone release; regional availability still needs to match the eventual permission scope.
- Apple's Add for Review validation was run without submitting. It explicitly requires content-rights information, published privacy information and age-rating answers. No rights or catalog-rating facts were fabricated. Account-level DSA details remain unverified.

## Native app and upstream source are distinct

Upstream main `7aa4badd85056efdb52ff999ae016d57d373d677` contains neither `ios/` nor `mobile-bridge/`. Xcode compiles the new SwiftUI target and local `NearFMCore` package, with no upstream Rust/web/contract build phase. The exported IPA has 15 entries and no HTML, JavaScript, WASM or Rust files. The new wallet bridge is separately hosted.

The missing upstream source license is therefore a repository-source question, not evidence that this IPA compiles upstream code. Catalog/music/artwork authorization is separate.

Build evidence: `ios/build/dachafm-build4-evidence.json`; source configuration: `ios/NearFM.xcodeproj/project.pbxproj`, `ios/scripts/generate_project.py` and `ios/Packages/NearFMCore/Package.swift`. The IPA SHA-256 is `a5699cc0f35f20c34e42e1e194b3d5c4f6ff531f9ad9285ce43806e0c7fecc6a`.

## Content Rights: hard submission blocker

The App Store Content Rights declaration is unresolved: the app accesses third-party content, and the evidence does not yet support affirming the necessary rights. Selecting an inaccurate answer does not resolve the blocker.

- The [public upstream repository](https://github.com/fastnear/near-fm) reports `license: null`; no source license was found in four branches or 105 main commits. [GitHub explains why public forking and unrestricted distribution differ](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
- The [official API guide](https://near.fm/skill.md) documents unauthenticated browsing, supporting intended programmatic access. It does not establish a blanket music/artwork license for independent apps. [Pinned guide](https://github.com/fastnear/near-fm/blob/7aa4badd85056efdb52ff999ae016d57d373d677/web/public/skill.md#6-browse-songs-trending-latest-top).
- [Community Rules](https://near.fm/rules) require uploader rights but contain no blanket downstream sublicense. No separate app-distribution permission was found; `/terms` returned 404.

Obtain applicable terms or written permission covering the API, streaming, metadata/artwork display and store screenshots, including scope and attribution. This is an evidence gap, not a claim that permission would be refused. See [Apple 5.2.2/5.2.3](https://developer.apple.com/app-store/review/guidelines/#intellectual-property) and the **unsent** `docs/release/upstream-permission-request.md`.

## Review risks and remaining checks

These are review risks or verification gaps, distinct from the unresolved Content Rights declaration:

- **Moderation:** Reporting links and artist hiding exist. Establish the operational reporting response, filtering and mature-content handling behind the upstream rules; complete the age rating against actual content and controls. [Apple 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).
- **Login interpretation:** Meteor authenticates a Dacha-owned cloud library, not an existing near.fm library. The third-party-client exception cannot be assumed from the app's description alone. Whether wallet signatures constitute first-party authentication or require an equivalent login option is an interpretation risk, not a categorical finding of rejection or an independent confirmed submission block. [Apple 4.8](https://developer.apple.com/app-store/review/guidelines/#login-services).
- **Reviewer access:** Guest features work without a wallet; review must also be able to exercise cloud sync/deletion. Tests reached Meteor, but real physical-device signature approval and return remain unverified. The audited database had zero retained accounts/sessions/libraries; this supplies no positive real-user evidence and does not prove a failed sign-in. [Review access guidance](https://developer.apple.com/app-store/review/guidelines/#before-you-submit).
- **Privacy:** Six categories are saved in the ASC draft, not published. Supabase logs are verified; external search/media retention remains unresolved. Upstream `TraceLayer` at its default DEBUG level can log full request URIs, including `q`; the deployed log level/retention are unknown. Public policy clarifies these limits. The build 4 manifest still declares only User ID and Other User Content; align any subsequent manifest with established practices. [Apple App Privacy](https://developer.apple.com/app-store/app-privacy-details/).
- **Draft verification:** Re-read saved review-contact phone/email before submission; field entry alone does not verify persistence.

## Submission checkpoint

Build 4 delivery and 31 core plus five UI tests are recorded in `docs/release/build-4-ui.md`. These do not establish rights or approval. Record submission only after App Store Connect confirms it; the current state remains preparation.
