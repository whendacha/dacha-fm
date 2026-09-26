# Dacha FM release status — 26 September 2026

## Build 4: processed and available in internal TestFlight

Build **1.0.0 (4)** fixes mini-player overlap on pagination and the bottom of library lists, and makes the authored app interface and public help/privacy pages English. Source song titles, artist/account names and user playlist names are preserved. The player occupies its own intrinsic-height row below the navigation stack, keeping pushed destinations clear without a hardcoded player-height estimate.

Fresh validation passed: **31 core tests, 5 iOS UI tests and 7 public release checks**. The UI regression reproduced the old overlap and now confirms catalog/artist pagination loads the next page. Long library, favorites and playlist screens were tested at the largest accessibility text size and with Russian device language. Live streaming, guest persistence and the real Meteor entry flow also passed. The compiled app declares English only; layout-test fixtures are absent from Release. English public pages match the deployed bytes.

The signed archive and App Store export passed. Apple accepted build 4 at **10:52:26 MSK (07:52:26 UTC) on 26 September 2026**. Processing completed, and build 4 (`ae8ee412-4201-41db-90f3-deb6c4bb5b89`) is assigned to the existing internal TestFlight group `91124dc5-3999-4c77-b0ec-84da99f8b3dd`. English testing instructions are saved. IPA SHA-256: `a5699cc0f35f20c34e42e1e194b3d5c4f6ff531f9ad9285ce43806e0c7fecc6a`. Local evidence is saved in `ios/build/dachafm-build4-evidence.json`; screenshots are in `ios/build/DachaFM-Build4-UIEvidence/`.

[Build 4 details](build-4-ui.md) · [iOS setup](../../ios/README.md)

## Build 3: processed and available in internal TestFlight

Build **1.0.0 (3)** adds optional Meteor-authenticated cloud synchronization for favorites, editable playlists and hidden authors. The server is deployed at `https://clxaqzlecqiypyiwgkxd.supabase.co/functions/v1/dacha-cloud`; its private database migration is applied. Guest listening and public music streaming work independently of cloud authentication.

Validation passed: **31 core tests, 11 PostgreSQL tests, 10 Edge tests, 8 bridge tests, 3 iOS UI tests and 9 deployed HTTPS checks**. Live checks used disposable sessions and verified cross-session library changes, account isolation, conflicts, logout and deletion. All disposable account/session records were removed; Supabase security advisors returned zero lints. The simulator played live audio to `0:05` and reached the real Meteor wallet screen through the cloud challenge flow. Actual wallet approval and the signed return remain unverified on a physical iPhone.

The Release archive **succeeded** at `ios/build/DachaFM-Build3.xcarchive`. Its compiled plist confirms bundle `com.whendacha.dachafm`, version `1.0.0 (3)` and the deployed cloud URL. **Apple accepted the build 3 upload at 10:34:11 MSK (07:34:11 UTC) on 26 September 2026** (`2026-09-26T07:34:11Z`). App Store Connect subsequently confirmed completed processing. Build 3 is assigned to the existing internal TestFlight group `91124dc5-3999-4c77-b0ec-84da99f8b3dd` for app `6816319440`, with one invited tester. Russian “What to Test” instructions are saved.

App Store Connect shows build ID `f4e21399-56e9-4fe2-a8a1-5274f79355a5` as completed, and its detail page lists the internal testing group. The local App Store export and IPA ZIP-integrity check passed; the exported package is `1.0.0 (3)` with SHA-256 `b40f2fc60ab7fc73354f38b6e5171c0fdd587661d072caae5f62487d4843f2f8`.

The deployed bridge SHA-256 matches source: `6ffa108cbc8641be96ebf41ed770c6a116f7dac27f926ed2c15cdd9c76df8852`. It preserves build 2's local signing statement and separately supports build 3's explicit cloud statement.

[Build 3 behavior and detailed evidence](build-3-cloud.md) · [iOS setup](../../ios/README.md) · [Cloud deployment](../../supabase/README.md)

## Previous confirmed TestFlight availability

Build **1.0.0 (1)** was uploaded, processed and made available to the invited internal TestFlight tester. It had no configured catalog or sign-in service. The user reported that music and authorization did not work. Build **1.0.0 (2)** addresses that configuration failure with direct public streaming and a separate local Meteor identity flow. Its three simulator UI tests and signed archive/export checks have passed. Apple received build 2 at **07:50:32 MSK (04:50:32 UTC) on 26 September 2026** and subsequently completed processing. Build 2 is available to the existing internal TestFlight group and its invited tester; Russian testing instructions are saved. No App Review submission or approval has occurred.


## Remaining release checks

1. Complete real Meteor signature approval and return, then verify the same wallet's library on two physical devices, offline editing, conflicts, background playback and interruptions.
2. Before public App Review submission, finish privacy disclosures, age rating, review access, metadata, moderation/support duties and any account-holder agreement requirements.
3. Confirm source/content permissions for public distribution. The inspected upstream repository has no explicit license. AI generation or public HTTP access is not recorded here as permission; no rights declaration has been submitted to Apple.

No App Review submission or approval has occurred. The app has no music generation, uploads, payments, wallet transactions or offline audio downloads.
