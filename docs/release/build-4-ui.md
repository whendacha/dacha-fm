# Dacha FM 1.0.0 (4): English interface and player layout

This update makes the app interface English, including navigation, playback controls, accessibility labels, settings, cloud-sync choices, account actions and error messages. Public help/privacy pages are also English. Song titles, artist names and user-created playlists retain their original text.

The mini-player now occupies its own intrinsic-height row below each navigation stack. The previous safe-area inset could leave pagination under the player after scrolling, especially on a pushed artist screen. The new layout reserves space for every destination without a fixed player-height estimate. The release retains the same bundle ID, public catalog, Meteor signing statements and cloud service. Existing libraries are preserved.

## Verification and delivery

- Five native UI tests passed on iPhone 17 Pro / iOS 26.5. Pagination tests tap both catalog and artist “Show more” controls above the mini-player and confirm the next page loads. Library, playlist and favorites tests reach their last rows at the largest accessibility text size. The layout tests request Russian device language and exercise the English app interface. Existing guest persistence, live audio playback and real Meteor entry tests also passed.
- The original layout failed the pagination regression; the fixed layout passed.
- 31 core tests passed. No Cyrillic authored interface text remains in app Swift sources, the wallet bridge or public pages. User-created names and source music metadata are unchanged.
- Seven public release checks passed, including live catalog/audio availability and the exact deployed wallet bridge hash. All three English public pages match the deployed bytes.
- The signed Release archive and App Store export passed, including strict signature and ZIP validation. The compiled app is `com.whendacha.dachafm`, `1.0.0 (4)`, with English as its only declared localization. Layout test fixtures are absent from the Release executable.
- IPA SHA-256: `a5699cc0f35f20c34e42e1e194b3d5c4f6ff531f9ad9285ce43806e0c7fecc6a`.
- Local evidence: `ios/build/dachafm-build4-evidence.json`, `ios/build/DachaFM-Build4-UIEvidence/`, `/tmp/DachaFM-Build4-AllUI.xcresult`.
- Apple accepted the upload at **10:52:26 MSK (07:52:26 UTC) on 26 September 2026**. Processing completed and build 4 is assigned to the existing internal TestFlight group. English testing instructions are saved. Apple build ID: `ae8ee412-4201-41db-90f3-deb6c4bb5b89`.

Actual wallet signature approval on a physical iPhone remains a separate acceptance check. This note does not claim App Review submission or approval.
