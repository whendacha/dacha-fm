import XCTest
@testable import NearFMCore

@MainActor
final class LibrarySyncTests: XCTestCase {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "library.json")
    }
    private func track(_ id: String) -> Track {
        Track(id: id, title: id, artistID: "32", artistName: "Author", audioURL: URL(string: "https://example.org/\(id).mp3")!, artworkURL: nil, duration: 60)
    }
    private func store(_ snapshot: LibrarySnapshot = .empty) throws -> LibraryStore {
        let value = try LibraryStore(fileURL: file())
        try value.enableCloudSync()
        try value.replace(snapshot)
        return value
    }

    func testOfflineEditsAndDirtyRevisionSurviveRestartThenUploadWithoutConflict() async throws {
        let url = file()
        let local = try LibraryStore(fileURL: url)
        try local.enableCloudSync()
        try local.toggleFavorite(track("a"))
        let revision = local.revision
        let reopened = try LibraryStore(fileURL: url)
        XCTAssertTrue(reopened.hasPendingChanges)
        XCTAssertEqual(reopened.revision, revision)
        XCTAssertTrue(reopened.cloudInitialized)
        let remote = MemoryRemote()
        let sync = LibrarySynchronizer(store: reopened, remote: remote)
        await sync.synchronize()
        XCTAssertEqual(sync.state, .synced)
        XCTAssertEqual(remote.snapshot.favorites.map(\.id), ["a"])
        XCTAssertEqual(remote.snapshot.version, 1)
        XCTAssertFalse(try LibraryStore(fileURL: url).hasPendingChanges)
    }

    func testLegacyWalletMigrationKeepsDataAndDoesNotUploadGuestStore() async throws {
        let url = file()
        let legacy = LibrarySnapshot(version: 0, favorites: [track("wallet")], playlists: [], blockedArtistIDs: [])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: url)
        let migrated = try LibraryStore(fileURL: url)
        try migrated.enableCloudSync()
        XCTAssertTrue(migrated.hasPendingChanges)
        let guest = try LibraryStore(fileURL: file())
        try guest.toggleFavorite(track("guest"))
        let remote = MemoryRemote()
        await LibrarySynchronizer(store: migrated, remote: remote).synchronize()
        XCTAssertEqual(remote.snapshot.favorites.map(\.id), ["wallet"])
        XCTAssertEqual(guest.snapshot.favorites.map(\.id), ["guest"])
    }

    func testRefreshAndEditsShareOneWorkerAndCannotApplyOldGETAfterPUT() async throws {
        let local = try store()
        let remote = MemoryRemote()
        let barrier = Barrier()
        remote.fetchBarrier = barrier
        let sync = LibrarySynchronizer(store: local, remote: remote)
        let first = Task { await sync.synchronize() }
        await barrier.waitUntilPaused()
        try local.toggleFavorite(track("a"))
        let second = Task { await sync.synchronize() }
        await Task.yield()
        XCTAssertEqual(remote.fetchCalls, 1)
        XCTAssertEqual(remote.putCalls, 0)
        barrier.resume()
        await first.value
        await second.value
        XCTAssertEqual(local.snapshot.favorites.map(\.id), ["a"])
        XCTAssertEqual(local.snapshot.version, remote.snapshot.version)
        XCTAssertFalse(local.hasPendingChanges)
    }

    func testEditDuringUploadSurvivesAcknowledgementAndIsUploadedNext() async throws {
        let local = try store()
        try local.toggleFavorite(track("a"))
        let remote = MemoryRemote()
        let barrier = Barrier()
        remote.putBarrier = barrier
        let sync = LibrarySynchronizer(store: local, remote: remote)
        let task = Task { await sync.synchronize() }
        await barrier.waitUntilPaused()
        try local.toggleFavorite(track("b"))
        barrier.resume()
        await task.value
        XCTAssertEqual(remote.putCalls, 2)
        XCTAssertEqual(remote.snapshot.favorites.map(\.id), ["a", "b"])
        XCTAssertFalse(local.hasPendingChanges)
    }

    func testConcurrentDevicesConflictAndExplicitDeviceChoicePreservesDeletionNameAndOrder() async throws {
        let a = track("a"), b = track("b")
        let base = LibrarySnapshot(version: 1, favorites: [a, b], playlists: [Playlist(id: "p", name: "Original", tracks: [a, b])], blockedArtistIDs: [])
        let local = try store(base)
        try local.toggleFavorite(a)
        try local.renamePlaylist(id: "p", name: "Device name")
        try local.moveTrack(in: "p", from: 0, to: 1)
        let other = try store(base)
        try other.toggleFavorite(track("other"))
        let remote = MemoryRemote(snapshot: base)
        await LibrarySynchronizer(store: other, remote: remote).synchronize()
        let sync = LibrarySynchronizer(store: local, remote: remote)
        await sync.synchronize()
        XCTAssertEqual(sync.state, .conflict)
        XCTAssertEqual(local.snapshot.favorites.map(\.id), ["b"])
        try await sync.useDevice()
        XCTAssertEqual(sync.state, .synced)
        XCTAssertEqual(remote.snapshot.favorites.map(\.id), ["b"])
        XCTAssertEqual(remote.snapshot.playlists[0].name, "Device name")
        XCTAssertEqual(remote.snapshot.playlists[0].tracks.map(\.id), ["b", "a"])
        XCTAssertEqual(remote.snapshot.version, 3)
    }

    func testCloudChoiceAndLostAcknowledgementDoNotResurrectRemovedEntries() async throws {
        let local = try store()
        try local.toggleFavorite(track("local"))
        let remote = MemoryRemote(snapshot: LibrarySnapshot(version: 1, favorites: [track("cloud")], playlists: [], blockedArtistIDs: []))
        let sync = LibrarySynchronizer(store: local, remote: remote)
        await sync.synchronize()
        XCTAssertEqual(sync.state, .conflict)
        try sync.useCloud()
        XCTAssertEqual(local.snapshot.favorites.map(\.id), ["cloud"])
        XCTAssertFalse(local.hasPendingChanges)
        try local.toggleFavorite(track("cloud"))
        remote.loseNextPutResponse = true
        await sync.synchronize()
        XCTAssertEqual(sync.state, .offline)
        XCTAssertTrue(local.hasPendingChanges)
        XCTAssertTrue(remote.snapshot.favorites.isEmpty)
        await sync.synchronize()
        XCTAssertEqual(sync.state, .synced)
        XCTAssertTrue(local.snapshot.favorites.isEmpty)
        XCTAssertFalse(local.hasPendingChanges)
        XCTAssertEqual(remote.putCalls, 1)
    }

    func testExpiredSessionPreservesPendingChangesForReauthentication() async throws {
        let local = try store()
        try local.toggleFavorite(track("offline"))
        let remote = MemoryRemote()
        remote.failNextFetch = LibrarySyncError.unauthorized
        let expired = LibrarySynchronizer(store: local, remote: remote)
        await expired.synchronize()
        XCTAssertEqual(expired.state, .reauthenticationRequired)
        XCTAssertTrue(local.hasPendingChanges)
        XCTAssertEqual(local.snapshot.favorites.map(\.id), ["offline"])
        expired.invalidate()
        let signedInAgain = LibrarySynchronizer(store: local, remote: remote)
        await signedInAgain.synchronize()
        XCTAssertEqual(remote.snapshot.favorites.map(\.id), ["offline"])
        XCTAssertFalse(local.hasPendingChanges)
    }

    func testRepeatedConflictWithoutNewRemoteVersionStopsAndKeepsPendingEdits() async throws {
        let local = try store()
        try local.toggleFavorite(track("pending"))
        let remote = MemoryRemote()
        remote.alwaysConflict = true
        let sync = LibrarySynchronizer(store: local, remote: remote)
        await sync.synchronize()
        XCTAssertEqual(sync.state, .offline)
        XCTAssertEqual(remote.putCalls, 3)
        XCTAssertTrue(local.hasPendingChanges)
        XCTAssertEqual(local.snapshot.favorites.map(\.id), ["pending"])
    }

    func testAccountInvalidationRejectsLateResponseAndCannotMutateNextAccount() async throws {
        let first = try store()
        let second = try store()
        let remote = MemoryRemote(snapshot: LibrarySnapshot(version: 1, favorites: [track("private-a")], playlists: [], blockedArtistIDs: []))
        let barrier = Barrier()
        remote.fetchBarrier = barrier
        let oldSync = LibrarySynchronizer(store: first, remote: remote)
        let task = Task { await oldSync.synchronize() }
        await barrier.waitUntilPaused()
        oldSync.invalidate()
        let nextRemote = MemoryRemote(snapshot: LibrarySnapshot(version: 2, favorites: [track("private-b")], playlists: [], blockedArtistIDs: []))
        await LibrarySynchronizer(store: second, remote: nextRemote).synchronize()
        barrier.resume()
        await task.value
        XCTAssertTrue(first.snapshot.favorites.isEmpty)
        XCTAssertEqual(second.snapshot.favorites.map(\.id), ["private-b"])
    }
    func testHideAndUnhideSyncBetweenTwoDevicesWithPreservedMemberships() async throws {
        let song = track("a")
        let base = LibrarySnapshot(version: 1, favorites: [song], playlists: [Playlist(id: "p", name: "Saved", tracks: [song])], blockedArtistIDs: [])
        let first = try store(base), second = try store(base)
        let remote = MemoryRemote(snapshot: base)
        let firstSync = LibrarySynchronizer(store: first, remote: remote)
        let secondSync = LibrarySynchronizer(store: second, remote: remote)
        try first.hideTrack(song)
        await firstSync.synchronize()
        await secondSync.synchronize()
        XCTAssertEqual(second.snapshot.hiddenTracks, [song])
        XCTAssertEqual(second.snapshot.favorites, [song])
        XCTAssertEqual(second.snapshot.playlists[0].tracks, [song])
        try second.unhideTrack(song.id)
        await secondSync.synchronize()
        await firstSync.synchronize()
        XCTAssertTrue(first.snapshot.hiddenTracks.isEmpty)
        XCTAssertEqual(first.snapshot.favorites, [song])
        XCTAssertEqual(first.snapshot.playlists[0].tracks, [song])
        XCTAssertEqual(first.snapshot.version, 3)
    }

    func testDifferentHiddenSongsCauseConflictInsteadOfLostAcknowledgement() async throws {
        let first = try store(), second = try store()
        let a = track("a"), b = track("b")
        try first.hideTrack(a)
        try second.hideTrack(b)
        let remote = MemoryRemote()
        await LibrarySynchronizer(store: second, remote: remote).synchronize()
        let sync = LibrarySynchronizer(store: first, remote: remote)
        await sync.synchronize()
        XCTAssertEqual(sync.state, .conflict)
        XCTAssertEqual(first.snapshot.hiddenTracks, [a])
        XCTAssertEqual(sync.remoteConflict?.hiddenTracks, [b])
        try await sync.useDevice()
        XCTAssertEqual(sync.state, .synced)
        XCTAssertEqual(remote.snapshot.hiddenTracks, [a])
    }

    func testLostHideAcknowledgementRecognizesSameUnorderedHiddenContent() async throws {
        let local = try store()
        let a = track("a"), b = track("b")
        try local.hideTrack(a)
        try local.hideTrack(b)
        let remote = MemoryRemote()
        remote.loseNextPutResponse = true
        let sync = LibrarySynchronizer(store: local, remote: remote)
        await sync.synchronize()
        XCTAssertEqual(sync.state, .offline)
        remote.snapshot.hiddenTracks.reverse()
        await sync.synchronize()
        XCTAssertEqual(sync.state, .synced)
        XCTAssertEqual(Set(local.snapshot.hiddenTracks.map(\.id)), Set(["a", "b"]))
        XCTAssertFalse(local.hasPendingChanges)
        XCTAssertEqual(remote.putCalls, 1)
    }

    func testHiddenMetadataDifferenceDoesNotMasqueradeAsAcknowledgement() async throws {
        let a = track("a")
        let changed = Track(id: a.id, title: "Changed", artistID: a.artistID, artistName: a.artistName, audioURL: a.audioURL, artworkURL: nil, duration: a.duration)
        let local = try store()
        try local.hideTrack(a)
        let remote = MemoryRemote(snapshot: LibrarySnapshot(version: 1, favorites: [], playlists: [], blockedArtistIDs: [], hiddenTracks: [changed]))
        let sync = LibrarySynchronizer(store: local, remote: remote)
        await sync.synchronize()
        XCTAssertEqual(sync.state, .conflict)
        XCTAssertEqual(local.snapshot.hiddenTracks, [a])
    }

    func testLegacyCloudResponseDecodesThenAcceptsFirstHide() async throws {
        let legacy = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(#"{"version":4,"favorites":[],"playlists":[],"blocked_artist_ids":[]}"#.utf8))
        let local = try store(legacy)
        let remote = MemoryRemote(snapshot: legacy)
        let sync = LibrarySynchronizer(store: local, remote: remote)
        await sync.synchronize()
        XCTAssertTrue(local.snapshot.hiddenTracks.isEmpty)
        try local.hideTrack(track("new"))
        await sync.synchronize()
        XCTAssertEqual(remote.snapshot.version, 5)
        XCTAssertEqual(remote.snapshot.hiddenTracks.map(\.id), ["new"])
    }

}

private extension LibrarySnapshot {
    static var empty: Self { .init(version: 0, favorites: [], playlists: [], blockedArtistIDs: []) }
}

@MainActor
private final class Barrier {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var paused = false
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            paused = true
            waiting?.resume()
            waiting = nil
        }
    }
    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class MemoryRemote: LibraryRemote {
    var snapshot: LibrarySnapshot
    var fetchCalls = 0
    var putCalls = 0
    var fetchBarrier: Barrier?
    var putBarrier: Barrier?
    var failNextFetch: Error?
    var loseNextPutResponse = false
    var alwaysConflict = false
    init(snapshot: LibrarySnapshot = .empty) { self.snapshot = snapshot }
    func fetchLibrary() async throws -> LibrarySnapshot {
        fetchCalls += 1
        let captured = snapshot
        if let barrier = fetchBarrier { fetchBarrier = nil; await barrier.pause() }
        if let error = failNextFetch { failNextFetch = nil; throw error }
        return captured
    }
    func putLibrary(_ incoming: LibrarySnapshot) async throws -> LibrarySnapshot {
        putCalls += 1
        if alwaysConflict { throw LibrarySyncError.conflict }
        if let barrier = putBarrier { putBarrier = nil; await barrier.pause() }
        guard snapshot.version == incoming.version else { throw LibrarySyncError.conflict }
        snapshot = incoming
        snapshot.version += 1
        if loseNextPutResponse { loseNextPutResponse = false; throw URLError(.networkConnectionLost) }
        return snapshot
    }
}
