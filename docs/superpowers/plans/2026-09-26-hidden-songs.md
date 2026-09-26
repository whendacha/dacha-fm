# Hidden songs implementation plan

**Goal:** Hide one song without hiding its artist, with reversible local and cloud persistence.

**Design:** A library gains `hiddenTracks: [Track]` (`hidden_tracks` in JSON), defaulting to an empty list when decoding old libraries. Track metadata lets Settings name each hidden song. Favorites and playlist membership remain saved; visible lists and all playback entry points exclude hidden IDs. Unhide restores visibility. Artist hiding retains its existing behavior.

**Compatibility:** Older clients omit the new field. The server preserves its stored value inside the existing locked compare-and-swap update; a new client's explicit empty array clears it. Session ownership, RLS and conflict rules remain unchanged. Release UI stays English and Dacha FM branded. Do not change wallet signing constants.

**Execution:** The user's standing instruction authorizes implementation and TestFlight delivery without repeated design approval. Core and cloud changes run independently; the main task owns native integration.

- [x] Core: add backward-compatible Codable storage, hide/unhide, explicit guest merge, hidden-only pending detection and sync content equality. Add queue removal preserving a surviving current item. Reorder only visible playlist slots. Verify migration, persistence, conflicts, reversible membership and queue edge cases with Swift tests.
- [x] Cloud: validate optional `hidden_tracks`, add a migration permitting the field, preserve it on legacy writes, and test explicit clearing, CAS and account isolation in disposable PostgreSQL and Edge tests. Review before production deployment.
- [x] iPhone: add Hide song to row/player/report actions and Hidden songs/Unhide in Settings. Derive visible catalog, artist and library lists; filter pagination/playback and scrub restored or remotely updated queues. Hide-current advances to the next available queued song while preserving playing/paused state.
- [x] UI verification: first demonstrate the missing Hide song action fails; then verify one song disappears while its artist's next song plays, hidden state survives relaunch, and Unhide restores Favorites and playlist membership. Recheck layout regression and real public playback.
- [x] Delivery: update help/privacy wording, increment to build 5, archive/export, deploy the compatible cloud change, and upload the tested build to the existing internal TestFlight group. Record actual receipts; public App Review remains a separate unresolved submission.
