# NearFMCore verification

The independent Swift package is at `ios/Packages/NearFMCore`. It exposes the agreed Track, Artist, Playlist, LibrarySnapshot, PlaybackQueue, and LibraryStore public APIs. Models encode and decode the mobile API's snake_case JSON.

Verification on 2026-09-26: `swift test --package-path ios/Packages/NearFMCore` completed with 8 tests and 0 failures. The tests cover author-only queue progression, append filtering, shuffle, duplicates, empty/end behavior, playlist persistence and order, favorites, artist blocking, repeated guest merge, corrupt-file preservation, version preservation, and wire JSON.

The package was tested on the local macOS Swift 6.3.3 toolchain. iOS simulator compilation and app integration remain root-task checks. `LibraryStore` local mutations deliberately retain the server snapshot version; callers must handle HTTP 409 by fetching and resolving the conflict before replacing the snapshot. `mergeGuest` combines favorites and playlists, but keeps the destination account's blocked-artist choices.
