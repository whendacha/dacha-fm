import Foundation

public enum LibraryStoreError: Error, Equatable {
    case invalidPlaylistName
    case playlistNotFound
    case invalidTrackIndex
    case blockedArtist
    case hiddenTrack
}

@MainActor
public final class LibraryStore {
    public private(set) var snapshot: LibrarySnapshot
    public private(set) var hasPendingChanges = false
    public private(set) var revision: UInt64 = 0
    public private(set) var cloudInitialized = false
    private let fileURL: URL

    private struct Persisted: Codable {
        let format: Int
        let snapshot: LibrarySnapshot
        let pending: Bool
        let revision: UInt64
        let cloudInitialized: Bool
    }

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // A corrupt or unreadable file is an error. Never replace it with an empty library.
            let data = try Data(contentsOf: fileURL)
            if let saved = try? JSONDecoder().decode(Persisted.self, from: data), saved.format == 1 {
                snapshot = saved.snapshot
                hasPendingChanges = saved.pending
                revision = saved.revision
                cloudInitialized = saved.cloudInitialized
            } else {
                snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
            }
        } else {
            snapshot = LibrarySnapshot(version: 0, favorites: [], playlists: [], blockedArtistIDs: [])
        }
    }

    public func toggleFavorite(_ track: Track) throws {
        try edit { value in
            guard !value.hiddenTracks.contains(where: { $0.id == track.id }) else { throw LibraryStoreError.hiddenTrack }
            if let index = value.favorites.firstIndex(where: { $0.id == track.id }) {
                value.favorites.remove(at: index)
            } else {
                guard !value.blockedArtistIDs.contains(track.artistID) else { throw LibraryStoreError.blockedArtist }
                value.favorites.append(track)
            }
        }
    }

    @discardableResult
    public func createPlaylist(name: String) throws -> String {
        let name = try Self.validName(name)
        let id = UUID().uuidString
        try edit { $0.playlists.append(Playlist(id: id, name: name, tracks: [])) }
        return id
    }

    public func renamePlaylist(id: String, name: String) throws {
        let name = try Self.validName(name)
        try edit { value in
            guard let index = value.playlists.firstIndex(where: { $0.id == id }) else { throw LibraryStoreError.playlistNotFound }
            value.playlists[index].name = name
        }
    }

    public func deletePlaylist(id: String) throws {
        try edit { value in
            guard let index = value.playlists.firstIndex(where: { $0.id == id }) else { throw LibraryStoreError.playlistNotFound }
            value.playlists.remove(at: index)
        }
    }

    public func add(_ track: Track, to playlistID: String) throws {
        try edit { value in
            guard !value.hiddenTracks.contains(where: { $0.id == track.id }) else { throw LibraryStoreError.hiddenTrack }
            guard !value.blockedArtistIDs.contains(track.artistID) else { throw LibraryStoreError.blockedArtist }
            guard let index = value.playlists.firstIndex(where: { $0.id == playlistID }) else { throw LibraryStoreError.playlistNotFound }
            if !value.playlists[index].tracks.contains(where: { $0.id == track.id }) {
                value.playlists[index].tracks.append(track)
            }
        }
    }

    public func remove(trackID: String, from playlistID: String) throws {
        try edit { value in
            guard let index = value.playlists.firstIndex(where: { $0.id == playlistID }) else { throw LibraryStoreError.playlistNotFound }
            value.playlists[index].tracks.removeAll { $0.id == trackID }
        }
    }

    public func moveTrack(in playlistID: String, from source: Int, to destination: Int) throws {
        try edit { value in
            guard let index = value.playlists.firstIndex(where: { $0.id == playlistID }) else { throw LibraryStoreError.playlistNotFound }
            let count = value.playlists[index].tracks.count
            guard (0..<count).contains(source), (0..<count).contains(destination) else { throw LibraryStoreError.invalidTrackIndex }
            let track = value.playlists[index].tracks.remove(at: source)
            value.playlists[index].tracks.insert(track, at: destination)
        }
    }

    /// Reorders only visible slots, leaving hidden songs in their saved positions.
    public func moveVisibleTrack(in playlistID: String, from source: Int, to destination: Int) throws {
        try edit { value in
            guard let index = value.playlists.firstIndex(where: { $0.id == playlistID }) else { throw LibraryStoreError.playlistNotFound }
            let hidden = Set(value.hiddenTracks.map(\.id))
            let blocked = Set(value.blockedArtistIDs)
            let slots = value.playlists[index].tracks.indices.filter {
                let track = value.playlists[index].tracks[$0]
                return !hidden.contains(track.id) && !blocked.contains(track.artistID)
            }
            guard slots.indices.contains(source), slots.indices.contains(destination) else { throw LibraryStoreError.invalidTrackIndex }
            var visible = slots.map { value.playlists[index].tracks[$0] }
            let moved = visible.remove(at: source)
            visible.insert(moved, at: destination)
            for (slot, track) in zip(slots, visible) { value.playlists[index].tracks[slot] = track }
        }
    }

    /// Hiding controls visibility; favorites and playlist membership remain intact.
    public func hideTrack(_ track: Track) throws {
        try edit { value in
            if !value.hiddenTracks.contains(where: { $0.id == track.id }) { value.hiddenTracks.append(track) }
        }
    }

    public func unhideTrack(_ trackID: String) throws {
        try edit { $0.hiddenTracks.removeAll { $0.id == trackID } }
    }

    public func blockArtist(_ artistID: String) throws {
        try edit { value in
            if !value.blockedArtistIDs.contains(artistID) { value.blockedArtistIDs.append(artistID) }
            value.favorites.removeAll { $0.artistID == artistID }
            for index in value.playlists.indices {
                value.playlists[index].tracks.removeAll { $0.artistID == artistID }
            }
        }
    }

    public func unblockArtist(_ artistID: String) throws {
        try edit { $0.blockedArtistIDs.removeAll { $0 == artistID } }
    }

    public func replace(_ replacement: LibrarySnapshot) throws {
        var normalized = try Self.normalized(replacement)
        normalized.version = replacement.version
        try commit(normalized, pending: false)
    }

    /// Upgrades a build 2 wallet library without treating it as an empty cloud copy.
    /// Guest stores never call this method and are uploaded only by explicit merge.
    public func enableCloudSync(legacyPending: Bool = false) throws {
        guard !cloudInitialized || legacyPending else { return }
        let hasContent = !snapshot.favorites.isEmpty || !snapshot.playlists.isEmpty
            || !snapshot.blockedArtistIDs.isEmpty || !snapshot.hiddenTracks.isEmpty
        try commit(snapshot, pending: hasPendingChanges || legacyPending || (!cloudInitialized && hasContent), cloud: true)
    }

    public func acknowledge(_ saved: LibrarySnapshot, sentRevision: UInt64) throws {
        if revision == sentRevision {
            try replace(saved)
        } else {
            var latest = snapshot
            latest.version = saved.version
            try commit(latest, pending: true)
        }
    }

    /// Explicitly chooses the device's complete content, including removals and order.
    public func rebaseLocal(on version: Int) throws {
        var local = snapshot
        local.version = version
        try commit(local, pending: true)
    }

    public func mergeGuest(_ guest: LibrarySnapshot) throws {
        try edit { value in
            var hiddenIDs = Set(value.hiddenTracks.map(\.id))
            value.hiddenTracks += guest.hiddenTracks.filter { hiddenIDs.insert($0.id).inserted }
            let blocked = Set(value.blockedArtistIDs)
            var favoriteIDs = Set(value.favorites.map(\.id))
            value.favorites += guest.favorites.filter {
                !blocked.contains($0.artistID) && favoriteIDs.insert($0.id).inserted
            }
            for playlist in guest.playlists {
                let name = try Self.validName(playlist.name)
                if let index = value.playlists.firstIndex(where: { $0.id == playlist.id }) {
                    var trackIDs = Set(value.playlists[index].tracks.map(\.id))
                    value.playlists[index].tracks += playlist.tracks.filter {
                        !blocked.contains($0.artistID) && trackIDs.insert($0.id).inserted
                    }
                } else {
                    var trackIDs = Set<String>()
                    let tracks = playlist.tracks.filter {
                        !blocked.contains($0.artistID) && trackIDs.insert($0.id).inserted
                    }
                    value.playlists.append(Playlist(id: playlist.id, name: name, tracks: tracks))
                }
            }
        }
    }

    private func edit(_ body: (inout LibrarySnapshot) throws -> Void) throws {
        var updated = snapshot
        try body(&updated)
        guard updated != snapshot else { return }
        try commit(updated, pending: true)
    }

    private func commit(_ value: LibrarySnapshot, pending: Bool, cloud: Bool? = nil) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let nextRevision = revision &+ 1
        let nextCloud = cloud ?? cloudInitialized
        let data = try JSONEncoder().encode(Persisted(format: 1, snapshot: value, pending: pending,
                                                     revision: nextRevision, cloudInitialized: nextCloud))
        try data.write(to: fileURL, options: .atomic)
        snapshot = value
        hasPendingChanges = pending
        revision = nextRevision
        cloudInitialized = nextCloud
    }

    private static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 100 else { throw LibraryStoreError.invalidPlaylistName }
        return trimmed
    }

    private static func normalized(_ input: LibrarySnapshot) throws -> LibrarySnapshot {
        let blocked = Array(Set(input.blockedArtistIDs)).sorted()
        let blockedSet = Set(blocked)
        var favoriteIDs = Set<String>()
        let favorites = input.favorites.filter { !blockedSet.contains($0.artistID) && favoriteIDs.insert($0.id).inserted }
        var playlistIDs = Set<String>()
        let playlists = try input.playlists.map { playlist -> Playlist in
            let name = try validName(playlist.name)
            guard playlistIDs.insert(playlist.id).inserted else { throw LibraryStoreError.invalidPlaylistName }
            var trackIDs = Set<String>()
            return Playlist(id: playlist.id, name: name, tracks: playlist.tracks.filter {
                !blockedSet.contains($0.artistID) && trackIDs.insert($0.id).inserted
            })
        }
        var hiddenIDs = Set<String>()
        let hidden = input.hiddenTracks.filter { hiddenIDs.insert($0.id).inserted }
        return LibrarySnapshot(version: input.version, favorites: favorites, playlists: playlists,
                               blockedArtistIDs: blocked, hiddenTracks: hidden)
    }
}
