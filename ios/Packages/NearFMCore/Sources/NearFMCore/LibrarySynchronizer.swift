import Foundation

public enum LibrarySyncError: Error {
    case unauthorized, conflict, invalidResponse
}

@MainActor
public protocol LibraryRemote {
    func fetchLibrary() async throws -> LibrarySnapshot
    func putLibrary(_ snapshot: LibrarySnapshot) async throws -> LibrarySnapshot
}

/// One coordinator owns all pulls and pushes for one authenticated account generation.
@MainActor
public final class LibrarySynchronizer {
    public enum State: Equatable { case idle, syncing, synced, offline, conflict, reauthenticationRequired }
    public private(set) var state: State = .idle
    public private(set) var failureMessage: String?
    public private(set) var remoteConflict: LibrarySnapshot?
    public var onChange: (() -> Void)?

    private let store: LibraryStore
    private let remote: any LibraryRemote
    private var valid = true
    private var requested = false
    private var work: Task<Void, Never>?

    public init(store: LibraryStore, remote: any LibraryRemote) {
        self.store = store
        self.remote = remote
    }

    public func invalidate() {
        valid = false
        requested = false
        work?.cancel()
        onChange = nil
    }

    public func synchronize() async {
        guard valid, state != .reauthenticationRequired else { return }
        requested = true
        if let work { await work.value; return }
        let task = Task { await self.run() }
        work = task
        await task.value
    }

    public func useCloud() throws {
        guard valid, work == nil, let remoteConflict else { return }
        try store.replace(remoteConflict)
        self.remoteConflict = nil
        requested = false
        update(.synced)
    }

    public func useDevice() async throws {
        guard valid, work == nil, let remoteConflict else { return }
        try store.rebaseLocal(on: remoteConflict.version)
        self.remoteConflict = nil
        await synchronize()
    }

    private func update(_ next: State, message: String? = nil) {
        state = next
        failureMessage = message
        onChange?()
    }

    private func run() async {
        defer { work = nil }
        var consecutiveConflicts = 0
        while valid && requested && !Task.isCancelled {
            requested = false
            update(.syncing)
            do {
                let fetched = try await remote.fetchLibrary()
                guard valid, !Task.isCancelled else { return }
                guard fetched.version >= 0 else { throw LibrarySyncError.invalidResponse }
                let current = store.snapshot
                if fetched.version < current.version {
                    // Server reset or a stale backend response must not silently roll back data.
                    remoteConflict = fetched
                    update(.conflict)
                    return
                }
                if store.hasPendingChanges {
                    if fetched.version != current.version {
                        if Self.sameContent(fetched, current) {
                            // A PUT may have committed even if its response was lost.
                            try store.replace(fetched)
                        } else {
                            remoteConflict = fetched
                            update(.conflict)
                            return
                        }
                    }
                } else {
                    try store.replace(fetched)
                }
                remoteConflict = nil
                onChange?()
                while valid && store.hasPendingChanges && !Task.isCancelled {
                    let sent = store.snapshot
                    let revision = store.revision
                    let saved: LibrarySnapshot
                    do { saved = try await remote.putLibrary(sent) }
                    catch LibrarySyncError.conflict {
                        consecutiveConflicts += 1
                        guard consecutiveConflicts < 3 else { throw LibrarySyncError.invalidResponse }
                        // Refetch in this same serialized worker before presenting a choice.
                        requested = true
                        break
                    }
                    consecutiveConflicts = 0
                    guard valid, !Task.isCancelled else { return }
                    guard sent.version < Int.max, saved.version == sent.version + 1 else {
                        throw LibrarySyncError.invalidResponse
                    }
                    try store.acknowledge(saved, sentRevision: revision)
                    onChange?()
                }
                guard valid, !Task.isCancelled else { return }
                if !store.hasPendingChanges { update(.synced) }
            } catch LibrarySyncError.unauthorized {
                guard valid else { return }
                requested = false
                update(.reauthenticationRequired)
                return
            } catch {
                guard valid, !Task.isCancelled else { return }
                requested = false
                update(.offline, message: error.localizedDescription)
                return
            }
        }
    }

    private static func sameContent(_ lhs: LibrarySnapshot, _ rhs: LibrarySnapshot) -> Bool {
        lhs.favorites == rhs.favorites && lhs.playlists == rhs.playlists
            && Set(lhs.blockedArtistIDs) == Set(rhs.blockedArtistIDs)
    }
}
