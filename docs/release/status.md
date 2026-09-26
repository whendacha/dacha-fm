# Dacha FM release status — 26 September 2026

## Build 3: cloud library ready, Apple upload blocked

Build **1.0.0 (3)** adds optional Meteor-authenticated cloud synchronization for favorites, editable playlists and hidden authors. The server is deployed at `https://clxaqzlecqiypyiwgkxd.supabase.co/functions/v1/dacha-cloud`; its private database migration is applied. Guest listening and public music streaming work independently of cloud authentication.

Validation passed: **31 core tests, 11 PostgreSQL tests, 10 Edge tests, 8 bridge tests, 3 iOS UI tests and 9 deployed HTTPS checks**. Live checks used disposable sessions and verified cross-session library changes, account isolation, conflicts, logout and deletion. All disposable account/session records were removed; Supabase security advisors returned zero lints. The simulator played live audio to `0:05` and reached the real Meteor wallet screen through the cloud challenge flow. Actual wallet approval and the signed return remain unverified on a physical iPhone.

The Release archive **succeeded** at `ios/build/DachaFM-Build3.xcarchive`. Its compiled plist confirms bundle `com.whendacha.dachafm`, version `1.0.0 (3)` and the deployed cloud URL. **Build 3 has not been uploaded**: Xcode export reports `No Accounts` and no distribution certificate. Xcode's developer account list is currently empty; the preceding builds used the normal Xcode account and Apple cloud signing. Normal Xcode sign-in to team `69AFW7DC78` is required to resume export and upload. No credentials or security settings were changed to work around this.

The deployed bridge SHA-256 matches source: `6ffa108cbc8641be96ebf41ed770c6a116f7dac27f926ed2c15cdd9c76df8852`. It preserves build 2's local signing statement and separately supports build 3's explicit cloud statement.

[Build 3 behavior and detailed evidence](build-3-cloud.md) · [iOS setup](../../ios/README.md) · [Cloud deployment](../../supabase/README.md)

## Most recent confirmed TestFlight delivery

Build **1.0.0 (1)** was uploaded, processed and made available to the invited internal TestFlight tester. It had no configured catalog or sign-in service. The user reported that music and authorization did not work. Build **1.0.0 (2)** addresses that configuration failure with direct public streaming and a separate local Meteor identity flow. Its three simulator UI tests and signed archive/export checks have passed. Apple received build 2 at **07:50:32 MSK (04:50:32 UTC) on 26 September 2026** and subsequently completed processing. Build 2 is available to the existing internal TestFlight group and its invited tester; Russian testing instructions are saved. No App Review submission or approval has occurred.


## Remaining release checks

1. Restore normal Xcode account access, export/upload build 3, verify Apple processing and add it to the existing internal group `91124dc5-3999-4c77-b0ec-84da99f8b3dd` for app `6816319440`.
2. Complete real Meteor signature approval and return, then verify the same wallet's library on two physical devices, offline editing, conflicts, background playback and interruptions.
3. Before public App Review submission, finish privacy disclosures, age rating, review access, metadata, moderation/support duties and any account-holder agreement requirements.
4. Confirm source/content permissions for public distribution. The inspected upstream repository has no explicit license. AI generation or public HTTP access is not recorded here as permission; no rights declaration has been submitted to Apple.

No App Review submission or approval has occurred. The app has no music generation, uploads, payments, wallet transactions or offline audio downloads.
