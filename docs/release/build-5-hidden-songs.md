# Dacha FM 1.0.0 (5): reversible hidden songs

Build 5 adds **Hide song** to song actions and the full player. A hidden song disappears from Listen, artist pages, Favorites, playlists and playback queues without hiding its artist. Settings → Hidden songs lists saved song metadata and offers **Unhide**. Favorites and playlist membership remain stored, so unhiding restores them. Reordering a playlist moves only visible entries and preserves hidden entries in their saved positions.

Hiding the current song selects the next surviving queued song, or the preceding survivor if it was the last entry. Playback stays paused when it was paused, and continues when it was playing or waiting for playback. An empty queue clears the player. Removing another queued song preserves an in-flight author-page advance. Restored queues, incoming cloud libraries and catalog pagination exclude hidden IDs; cached catalog metadata remains available for immediate unhiding.

Hidden songs persist in the device library and the optional account cloud library. Old local snapshots decode with an empty hidden list. The deployed server preserves hidden songs when an older client omits `hidden_tracks`; an explicit empty list from a new client clears them. Guest import merges hidden songs explicitly, using account metadata first. Existing conflict handling, account isolation and artist-block behavior remain in place. The authored interface remains English; song titles, artist names and user playlist names retain their original text.

## Validation

| Check | Recorded result |
| --- | --- |
| Regression before implementation | One UI test failed because the song menu had no Hide song action. `/tmp/DachaFM-HideSong-Red.log` |
| Swift core | **48 tests, 0 failures**; covers legacy decoding, normalization, reversible membership, visible playlist reorder, guest merge, two-store synchronization/conflicts and queue removal. `/tmp/dachafm-hidden-core-green.log` |
| Native UI | **7 tests, 0 failures** on iPhone 17 Pro / iOS 26.5 Simulator. `/tmp/DachaFM-Build5-AllUI.log` and `/tmp/DachaFM-Build5-AllUI.xcresult` |
| Cloud | **15 Edge tests, 15 PostgreSQL tests and 14 live checks passed**; deployment and fixture cleanup are recorded in [cloud verification](build-5-cloud-verification.md). |
| Distribution | Release archive and App Store export succeeded. `/tmp/dachafm-build5-archive.log` and `/tmp/dachafm-build5-export.log` |

The UI suite verifies hide-current advancement, persistence across relaunch, restoration of Favorites and playlist membership, paused-player behavior and clearing the sole queued song. It also reruns reachable pagination, large-text library layout, guest persistence, live public audio progress and the real Meteor wallet entry screen. Fixture-based layout tests use isolated stores. Release executable checks exclude the layout fixture strings.

The archive passes strict code-signature verification. The exported IPA passes ZIP integrity checks and contains `com.whendacha.dachafm`, version **1.0.0 (5)**, with English as its only declared localization. Its privacy manifest declares six known categories: User ID, Other User Content, Product Interaction, Coarse Location, Performance Data and Other Diagnostic Data. All are linked for App Functionality, none for tracking; Product Interaction also declares Product Personalization. This binary alignment does not resolve the external provider-retention questions in the [privacy audit](app-privacy-audit.md).

The published English support and privacy pages match their local source bytes. An independent read-only review found no additional critical regression in account transitions, cloud merge/restore or late pagination responses.

## Artifact and delivery record

- Build source: `d386c886186cb69dcae5431b45484789be307344`.
- IPA: `ios/build/DachaFM-Build5-AppStore/DachaFM.ipa`.
- IPA SHA-256: `a176e13bdfeb9b42fe3ca1ba3d5ab27de8cd02eecf16123cb8f4d613490b1bdf`.
- Ignored local evidence: `ios/build/dachafm-build5-evidence.json`, including source hashes, compiled configuration, test summary, cloud receipt and artifact checks. Local configuration secrets are excluded.
- UI attachments: `ios/build/DachaFM-Build5-UIEvidence/`.
- Apple accepted the upload at **13:34:10 MSK (10:34:10 UTC) on 26 September 2026**. `/tmp/dachafm-build5-upload.log` records “Upload succeeded” and reports that the uploaded package is processing. App Store Connect subsequently confirmed completed processing. Build `4f1e8ed9-929f-4baf-8994-6b5560b22d7f` is assigned to the existing internal TestFlight group `91124dc5-3999-4c77-b0ec-84da99f8b3dd`; English testing instructions are saved. The English App Store draft now selects build 5 and describes individual-song hiding; it remains in Prepare for Submission.

Real wallet signature approval and synchronization between two physical devices remain separate acceptance checks. This report establishes neither App Review submission nor approval; the unresolved public-submission requirements remain in the [review-readiness report](app-review-readiness.md).
