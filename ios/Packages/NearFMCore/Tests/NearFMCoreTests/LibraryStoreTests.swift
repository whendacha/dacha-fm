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
}
