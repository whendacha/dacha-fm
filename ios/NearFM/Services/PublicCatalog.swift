import Foundation
import NearFMCore

/// Public, read-only catalog transport, isolated from all private account credentials.
actor PublicCatalog {
    private let baseURL = URL(string: "https://api.near.fm")!
    private let session: URLSession
    private let pageSize = 100
    private let scanLimit = 3
    private var cache: [URL: (date: Date, data: Data)] = [:]
    private var pending: [URL: Task<Data, Error>] = [:]
    private var knownCounts: [String: Int] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 35
        session = URLSession(configuration: configuration)
    }

    func tracks(query: String = "", artistID: String? = nil, page: Int = 1) async throws -> TrackPage {
        var cursor = max(page, 1)
        for attempt in 0..<scanLimit {
            try Task.checkCancellation()
            // Author queues must use uploader identity, never a full-text search for the name.
            let source = try await songs(query: artistID == nil ? query : "", page: cursor)
            let tracks = source.tracks(artistID: artistID)
            if !tracks.isEmpty || !source.hasMore || attempt == scanLimit - 1 {
                return TrackPage(tracks: tracks, page: cursor, hasMore: source.hasMore)
            }
            cursor += 1
        }
        return TrackPage(tracks: [], page: cursor, hasMore: false)
    }

    func artists(query: String = "", page: Int = 1) async throws -> ArtistPage {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var found: [String: Artist] = [:]
        var order: [String] = []
        // A full slug allows discovery even if the artist is absent from recent pages.
        if page <= 1, Self.isSlug(search), let profile = try? await profile(slug: search) {
            if let song = profile.songs.first(where: { $0.track != nil }) {
                let count = profile.totalSongs ?? (profile.songs.count < 50 ? profile.songs.count : -1)
                knownCounts[song.artistID] = count
                found[song.artistID] = Artist(id: song.artistID, name: profile.displayName ?? song.artistName,
                    artworkURL: PublicCatalogSong.httpsURL(profile.avatarURL) ?? song.track?.artworkURL,
                    trackCount: count)
                order.append(song.artistID)
            }
        }
        var cursor = max(page, 1)
        for attempt in 0..<scanLimit {
            try Task.checkCancellation()
            // Search song text and author names independently. Upstream q does not index authors.
            let source = try await songs(query: "", page: cursor)
            for song in source.songs where song.track != nil {
                guard search.isEmpty || song.artistName.localizedCaseInsensitiveContains(search)
                        || song.uploaderSlug.localizedCaseInsensitiveContains(search) else { continue }
                guard found[song.artistID] == nil else { continue }
                found[song.artistID] = Artist(id: song.artistID, name: song.artistName,
                    artworkURL: song.track?.artworkURL, trackCount: knownCounts[song.artistID] ?? -1)
                order.append(song.artistID)
            }
            if !found.isEmpty || !source.hasMore || attempt == scanLimit - 1 {
                return ArtistPage(artists: order.compactMap { found[$0] }, page: cursor, hasMore: source.hasMore)
            }
            cursor += 1
        }
        return ArtistPage(artists: [], page: cursor, hasMore: false)
    }

    private func songs(query: String, page: Int) async throws -> PublicCatalogPage {
        var items = [URLQueryItem(name: "sort", value: "latest"),
                     URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "limit", value: String(pageSize))]
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await read(path: "api/songs", query: items)
    }

    private struct Profile: Decodable {
        let songs: [PublicCatalogSong]
        let totalSongs: Int?
        let displayName: String?
        let avatarURL: String?
        enum CodingKeys: String, CodingKey {
            case songs
            case totalSongs = "total_songs", displayName = "display_name", avatarURL = "avatar_url"
        }
    }

    private func profile(slug: String) async throws -> Profile {
        try await read(path: "api/users/\(slug)", query: [])
    }

    private static func isSlug(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64
            && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-").contains($0) }
    }

    private func read<Response: Decodable>(path: String, query: [URLQueryItem]) async throws -> Response {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw MobileAPIError.invalidResponse
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw MobileAPIError.invalidResponse }
        let data: Data
        if let cached = cache[url], Date().timeIntervalSince(cached.date) < 120 {
            data = cached.data
        } else if let task = pending[url] {
            data = try await task.value
        } else {
            let task = Task { [session] in
                var request = URLRequest(url: url)
                request.httpShouldHandleCookies = false
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw MobileAPIError.invalidResponse }
                guard (200..<300).contains(response.statusCode) else { throw MobileAPIError.server(response.statusCode, "") }
                return data
            }
            pending[url] = task
            defer { pending.removeValue(forKey: url) }
            data = try await task.value
            if cache.count >= 16, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key {
                cache.removeValue(forKey: oldest)
            }
            cache[url] = (Date(), data)
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw MobileAPIError.invalidResponse }
    }
}
