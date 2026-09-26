import Foundation

public struct Track: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let artistID: String
    public let artistName: String
    public let audioURL: URL
    public let artworkURL: URL?
    public let duration: Double?

    public init(id: String, title: String, artistID: String, artistName: String,
                audioURL: URL, artworkURL: URL?, duration: Double?) {
        self.id = id
        self.title = title
        self.artistID = artistID
        self.artistName = artistName
        self.audioURL = audioURL
        self.artworkURL = artworkURL
        self.duration = duration
    }

    enum CodingKeys: String, CodingKey {
        case id, title, duration
        case artistID = "artist_id"
        case artistName = "artist_name"
        case audioURL = "audio_url"
        case artworkURL = "artwork_url"
    }
}

public struct Artist: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let artworkURL: URL?
    public let trackCount: Int

    public init(id: String, name: String, artworkURL: URL?, trackCount: Int) {
        self.id = id
        self.name = name
        self.artworkURL = artworkURL
        self.trackCount = trackCount
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case artworkURL = "artwork_url"
        case trackCount = "track_count"
    }
}

public struct Playlist: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var tracks: [Track]

    public init(id: String, name: String, tracks: [Track]) {
        self.id = id
        self.name = name
        self.tracks = tracks
    }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var favorites: [Track]
    public var playlists: [Playlist]
    public var blockedArtistIDs: [String]

    public init(version: Int, favorites: [Track], playlists: [Playlist], blockedArtistIDs: [String]) {
        self.version = version
        self.favorites = favorites
        self.playlists = playlists
        self.blockedArtistIDs = blockedArtistIDs
    }

    enum CodingKeys: String, CodingKey {
        case version, favorites, playlists
        case blockedArtistIDs = "blocked_artist_ids"
    }
}
