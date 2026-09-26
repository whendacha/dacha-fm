import Foundation

public enum LibraryStoreError: Error, Equatable {
    case invalidPlaylistName
    case playlistNotFound
    case invalidTrackIndex
    case blockedArtist
}

@MainActor
public final class LibraryStore {
    public private(set) var snapshot: LibrarySnapshot
    private let fileURL: URL

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // A corrupt or unreadable file is an error. Never replace it with an empty library.
            snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: fileURL))
        } else {
            snapshot = LibrarySnapshot(version: 0, favorites: [], playlists: [], blockedArtistIDs: [])
        }
    }

    public func toggleFavorite(_ track: Track) throws {
        try edit { value in
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
        try persist(normalized)
        snapshot = normalized
    }

    public func mergeGuest(_ guest: LibrarySnapshot) throws {
        try edit { value in
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
        try persist(updated)
        snapshot = updated
    }

    private func persist(_ value: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: fileURL, options: .atomic)
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
        return LibrarySnapshot(version: input.version, favorites: favorites, playlists: playlists, blockedArtistIDs: blocked)
    }
}
