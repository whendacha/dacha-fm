# Dacha FM App Review readiness

Status as of 26 September 2026: **APP REVIEW NOT SUBMITTED.** Dacha FM **1.0.0 (4)** remains available in the existing internal TestFlight group. TestFlight delivery is not App Store submission or approval. This document records the bounded audit findings and remaining evidence needed for a defensible submission; it does not guarantee acceptance.

## Native app and upstream source are distinct

The upstream `fastnear/near-fm` main revision inspected was `7aa4badd85056efdb52ff999ae016d57d373d677`. It contains neither `ios/` nor `mobile-bridge/`. The Dacha FM Xcode target compiles the newly added SwiftUI sources in `ios/NearFM/` and the new local `ios/Packages/NearFMCore` package. It has no Rust, upstream web or contract build phase. The exported build 4 IPA contained 15 entries and no HTML, JavaScript, WASM or Rust files. The new wallet bridge is separately hosted on GitHub Pages.

Consequently, the absence of an upstream source license is not evidence that the IPA compiles upstream implementation code. Repository source distribution and the native binary must be assessed separately. Access to the third-party catalog, artwork and music remains a separate permission question.

Build evidence: `ios/build/dachafm-build4-evidence.json`; source configuration: `ios/NearFM.xcodeproj/project.pbxproj`, `ios/scripts/generate_project.py` and `ios/Packages/NearFMCore/Package.swift`. The IPA SHA-256 is `a5699cc0f35f20c34e42e1e194b3d5c4f6ff531f9ad9285ce43806e0c7fecc6a`.

## What the published sources establish

- The [upstream repository](https://github.com/fastnear/near-fm) is public. [GitHub repository metadata](https://api.github.com/repos/fastnear/near-fm) returned `license: null`. No LICENSE/COPYING/NOTICE files were found in the four published branches or the complete 105-commit main history. README and package manifests contained no source license grant. GitHub permits public-repository viewing/forking on its platform; that does not by itself grant unrestricted external distribution rights. [GitHub licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
- near.fm intentionally publishes a public integration guide. Its song-browsing section says, “No auth required.” This supports intended programmatic catalog access. The guide does not supply a blanket license for every song/artwork in an independently distributed player. [Official guide](https://near.fm/skill.md), [pinned source](https://github.com/fastnear/near-fm/blob/7aa4badd85056efdb52ff999ae016d57d373d677/web/public/skill.md#6-browse-songs-trending-latest-top).
- The [Community Rules](https://near.fm/rules) require uploaders to hold rights to music and images. No downstream blanket sublicense was found there. The platform's AI-generated-music description does not establish that all lyrics, audio and artwork are rights-free. [About near.fm](https://near.fm/about).
- No separate published terms page granting independent app/catalog redistribution was found in the inspected site navigation or source tree. `/terms` returned HTTP 404. This is an unverified permission gap, not a claim that the operator would refuse permission.

## Remaining material submission blockers and checks

### Third-party catalog and content authorization

Obtain a written permission statement or applicable published terms covering Dacha FM's API use and direct streaming/display of the catalog, artwork and metadata in an independently branded iOS app. Establish the scope of the operator's authority over uploaded content, any required attribution, and any limitations. If the operator cannot authorize the entire catalog, identify an authorized subset or another sufficient rights basis. Store screenshots containing third-party artwork also need a supported rights basis.

Apple 5.2.2 and 5.2.3 require authorization for relevant third-party service/content use and address streaming as well as downloading. Technical availability is not the same as evidence sufficient for a content-rights declaration. [Apple intellectual-property guidelines](https://developer.apple.com/app-store/review/guidelines/#intellectual-property). A draft request is in `docs/release/upstream-permission-request.md`; it has **not been sent**.

### Catalog moderation and age-rating evidence

The native app offers reporting links to the source and the ability to hide an artist. Upstream community rules describe moderation. The remaining review evidence should establish who receives reports, how concerns receive timely responses, what material is filtered before appearing in the public feed, and how incidental mature content is handled. An upstream policy and a link alone do not prove the operational behavior. Complete age-rating answers against the actual accessible catalog and controls. [Apple user-generated-content guidelines](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).

### Optional wallet account and reviewer access

Guest listening, local favorites and playlists are available without a wallet. Meteor sign-in establishes a Dacha FM cloud account for optional library synchronization. It does not log into a near.fm account or retrieve that user's near.fm library. Therefore describing the product as a third-party player does not, by itself, establish Apple's specific third-party-client login exception. Explain the actual wallet authentication architecture and resolve any equivalent-login requirement with that architecture in view. [Apple login-services guideline](https://developer.apple.com/app-store/review/guidelines/#login-services).

Provide a practical way for App Review to exercise optional cloud sync and deletion. Existing automated checks cover the real Meteor entry screen and service components, but physical-device wallet approval and the complete signed return remain unverified. A read-only production database aggregate on the audit date found zero retained accounts, sessions and libraries. This does not prove a sign-in failure or rule out a previously deleted account; it supplies no positive evidence of a current real-user cloud library. Do not represent the guest experience as a complete demonstration of cloud features. [Apple submission preparation](https://developer.apple.com/app-store/review/guidelines/#before-you-submit).

### Accurate privacy disclosures

Cloud identifiers and library content are collected. Live aggregate inspection also confirmed retained provider IPs, approximate city/country, HTTP/device metadata, security network fingerprints and request durations. The app's lack of its own analytics logger does not eliminate this infrastructure collection. Provider logs/backups have retention separate from account deletion. No fixed retention days have been verified.

Search text is transmitted to `api.near.fm`; upstream search/media request retention remains unverified. Do not assert that search history is never collected. Use `docs/release/app-privacy-audit.md` for the source evidence, category recommendations and exact aggregate-query method. The public policy was clarified, while the build 4 embedded manifest still declares only User ID and Other User Content. Reconcile the final App Store Connect answers and any subsequent binary manifest with actual practices. This audit does not claim App Store Connect privacy answers have been configured. [Apple App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/).

## Submission checkpoint

Build 4 delivery and its 31 core plus five UI tests are recorded in `docs/release/build-4-ui.md`. Those checks support functionality; they do not establish content permission, completed wallet acceptance, moderation operations or App Review approval. Keep the application in preparation until the material assertions above can be answered accurately. Record the actual submission receipt/status only after App Store Connect confirms it.
