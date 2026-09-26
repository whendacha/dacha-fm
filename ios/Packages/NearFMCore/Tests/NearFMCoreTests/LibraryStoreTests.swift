import XCTest
@testable import NearFMCore

@MainActor
final class LibraryStoreTests: XCTestCase {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
    }

    private func track(_ id: String, artist: String = "a") -> Track {
        Track(id: id, title: id, artistID: artist, artistName: artist,
              audioURL: URL(string: "https://example.org/\(id).mp3")!, artworkURL: nil, duration: 12)
    }

    func testReopensWithOrderedPlaylistAndDeduplicatedTracks() throws {
        let url = file()
        let store = try LibraryStore(fileURL: url)
        let id = try store.createPlaylist(name: "  Road trip  ")
        try store.add(track("one"), to: id)
        try store.add(track("two"), to: id)
        try store.add(track("one"), to: id)
        try store.moveTrack(in: id, from: 0, to: 1)
        try store.renamePlaylist(id: id, name: "New name")
        XCTAssertEqual(store.snapshot.playlists[0].tracks.map(\.id), ["two", "one"])
        XCTAssertEqual(store.snapshot.playlists[0].name, "New name")
        XCTAssertEqual(try LibraryStore(fileURL: url).snapshot, store.snapshot)
    }

    func testFavoritesBlockingAndGuestMerge() throws {
        let store = try LibraryStore(fileURL: file())
        try store.toggleFavorite(track("one"))
        try store.toggleFavorite(track("one"))
        XCTAssertTrue(store.snapshot.favorites.isEmpty)
        let playlistID = try store.createPlaylist(name: "Saved")
        try store.add(track("one"), to: playlistID)
        let guest = LibrarySnapshot(version: 0, favorites: [track("one"), track("one"), track("other", artist: "b")],
                                    playlists: [Playlist(id: "guest", name: "Guest", tracks: [track("one")])], blockedArtistIDs: [])
        try store.mergeGuest(guest)
        XCTAssertEqual(store.snapshot.favorites.map(\.id), ["one", "other"])
        try store.mergeGuest(guest)
        XCTAssertEqual(store.snapshot.playlists.filter { $0.id == "guest" }.count, 1)
        XCTAssertEqual(store.snapshot.playlists.count, 2)
        try store.blockArtist("a")
        XCTAssertEqual(store.snapshot.favorites.map(\.id), ["other"])
        XCTAssertTrue(store.snapshot.playlists.allSatisfy { $0.tracks.allSatisfy { $0.artistID != "a" } })
        try store.mergeGuest(guest)
        XCTAssertEqual(store.snapshot.favorites.map(\.id), ["other"])
        try store.unblockArtist("a")
        XCTAssertTrue(store.snapshot.blockedArtistIDs.isEmpty)
    }

    func testCorruptFileThrowsWithoutOverwritingIt() throws {
        let url = file()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bad = Data("invalid json".utf8)
        try bad.write(to: url)
        XCTAssertThrowsError(try LibraryStore(fileURL: url))
        XCTAssertEqual(try Data(contentsOf: url), bad)
    }

    func testInvalidNameAndVersionPreservation() throws {
        let store = try LibraryStore(fileURL: file())
        XCTAssertThrowsError(try store.createPlaylist(name: " \n "))
        try store.replace(LibrarySnapshot(version: 7, favorites: [track("one")], playlists: [], blockedArtistIDs: []))
        try store.toggleFavorite(track("two"))
        XCTAssertEqual(store.snapshot.version, 7)
    }
    func testHiddenTracksPersistAndUnhidePreservesOriginalMemberships() throws {
        let url = file()
        let store = try LibraryStore(fileURL: url)
        let first = track("one"), second = track("two")
        try store.toggleFavorite(first)
        let playlist = try store.createPlaylist(name: "Saved")
        try store.add(first, to: playlist)
        try store.add(second, to: playlist)
        try store.hideTrack(first)
        let revision = store.revision
        try store.hideTrack(first)
        XCTAssertEqual(store.revision, revision, "Hiding twice is an idempotent edit")
        let reopened = try LibraryStore(fileURL: url)
        XCTAssertEqual(reopened.snapshot.hiddenTracks, [first])
        XCTAssertTrue(reopened.hasPendingChanges)
        XCTAssertEqual(reopened.snapshot.favorites, [first])
        XCTAssertEqual(reopened.snapshot.playlists[0].tracks, [first, second])
        try reopened.unhideTrack(first.id)
        XCTAssertTrue(reopened.snapshot.hiddenTracks.isEmpty)
        XCTAssertEqual(reopened.snapshot.favorites, [first])
        XCTAssertEqual(reopened.snapshot.playlists[0].tracks, [first, second])
        XCTAssertTrue(try LibraryStore(fileURL: url).snapshot.hiddenTracks.isEmpty)
    }

    func testHiddenTrackCannotBeAddedOrToggleExistingFavorite() throws {
        let store = try LibraryStore(fileURL: file())
        let song = track("one")
        try store.toggleFavorite(song)
        let playlist = try store.createPlaylist(name: "Saved")
        try store.hideTrack(song)
        let before = store.snapshot
        XCTAssertThrowsError(try store.toggleFavorite(song)) { XCTAssertEqual($0 as? LibraryStoreError, .hiddenTrack) }
        XCTAssertThrowsError(try store.add(song, to: playlist)) { XCTAssertEqual($0 as? LibraryStoreError, .hiddenTrack) }
        XCTAssertEqual(store.snapshot, before)
        try store.unhideTrack(song.id)
        try store.add(song, to: playlist)
        XCTAssertEqual(store.snapshot.playlists[0].tracks, [song])
    }

    func testHiddenNormalizationAndGuestMergePreserveAccountMetadataAndMemberships() throws {
        let store = try LibraryStore(fileURL: file())
        let original = track("one"), duplicate = Track(id: "one", title: "Guest title", artistID: "a", artistName: "a", audioURL: URL(string: "https://example.org/guest.mp3")!, artworkURL: nil, duration: nil)
        let other = track("two")
        try store.replace(LibrarySnapshot(version: 3, favorites: [original], playlists: [], blockedArtistIDs: ["blocked"], hiddenTracks: [original, duplicate]))
        XCTAssertEqual(store.snapshot.hiddenTracks, [original])
        let guest = LibrarySnapshot(version: 0, favorites: [other], playlists: [Playlist(id: "guest", name: "Guest", tracks: [other])], blockedArtistIDs: ["a"], hiddenTracks: [duplicate, other, other])
        try store.mergeGuest(guest)
        XCTAssertEqual(store.snapshot.hiddenTracks, [original, other])
        XCTAssertEqual(store.snapshot.favorites, [original, other])
        XCTAssertEqual(store.snapshot.playlists[0].tracks, [other])
        XCTAssertEqual(store.snapshot.blockedArtistIDs, ["blocked"], "Guest artist blocking must not change account policy")
        let revision = store.revision
        try store.mergeGuest(guest)
        XCTAssertEqual(store.revision, revision)
    }

    func testHiddenOnlyLibraryBecomesPendingWhenCloudSyncIsEnabled() throws {
        let store = try LibraryStore(fileURL: file())
        try store.replace(LibrarySnapshot(version: 0, favorites: [], playlists: [], blockedArtistIDs: [], hiddenTracks: [track("one")]))
        XCTAssertFalse(store.hasPendingChanges)
        try store.enableCloudSync()
        XCTAssertTrue(store.hasPendingChanges)
        XCTAssertEqual(store.snapshot.hiddenTracks.map(\.id), ["one"])
    }

    func testLegacyBuild4PersistedEnvelopeLoadsWithNoHiddenTracks() throws {
        let url = file()
        let data = Data(#"{"format":1,"snapshot":{"version":4,"favorites":[],"playlists":[],"blocked_artist_ids":[]},"pending":true,"revision":9,"cloudInitialized":true}"#.utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        let legacy = try LibraryStore(fileURL: url)
        XCTAssertEqual(legacy.snapshot.version, 4)
        XCTAssertTrue(legacy.snapshot.hiddenTracks.isEmpty)
        XCTAssertTrue(legacy.hasPendingChanges)
        XCTAssertEqual(legacy.revision, 9)
        XCTAssertTrue(legacy.cloudInitialized)
    }

    func testVisibleReorderKeepsHiddenSlotsUntilUnhidden() throws {
        let store = try LibraryStore(fileURL: file())
        let a = track("a"), hidden = track("hidden"), b = track("b"), c = track("c")
        try store.replace(LibrarySnapshot(version: 1, favorites: [], playlists: [Playlist(id: "p", name: "Saved", tracks: [a, hidden, b, c])], blockedArtistIDs: [], hiddenTracks: [hidden]))
        try store.moveVisibleTrack(in: "p", from: 2, to: 0)
        XCTAssertEqual(store.snapshot.playlists[0].tracks, [c, hidden, a, b])
        XCTAssertThrowsError(try store.moveVisibleTrack(in: "p", from: 3, to: 0)) { XCTAssertEqual($0 as? LibraryStoreError, .invalidTrackIndex) }
        try store.unhideTrack(hidden.id)
        XCTAssertEqual(store.snapshot.playlists[0].tracks, [c, hidden, a, b])
    }

}
