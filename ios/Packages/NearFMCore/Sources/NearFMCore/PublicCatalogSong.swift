import Foundation

/// Read-only mapping of the public catalog. Financial fields, lyrics and wallet data
/// are deliberately not retained by the listener.
public struct PublicCatalogSong: Decodable, Sendable {
    public let uuid: String
    public let uploaderID: Int
    public let uploaderSlug: String
    public let uploaderDisplayName: String?
    public let title: String
    public let audioURL: String?
    public let coverImageURL: String?
    public let duration: Double?
    public let isHidden: Bool?
    public let isDeleted: Bool?
    public let isValidated: Bool?

    enum CodingKeys: String, CodingKey {
        case uuid, title
        case uploaderID = "uploader_id", uploaderSlug = "uploader_account_id"
        case uploaderDisplayName = "uploader_display_name"
        case audioURL = "audio_url", coverImageURL = "cover_image_url"
        case duration = "audio_duration_seconds"
        case isHidden = "is_hidden", isDeleted = "is_deleted", isValidated = "is_validated"
    }

    public var artistID: String { String(uploaderID) }
    public var artistName: String {
        let name = uploaderDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? uploaderSlug : name
    }

    public var track: Track? {
        guard !uuid.isEmpty, uploaderID > 0, !uploaderSlug.isEmpty,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isHidden != true, isDeleted != true, isValidated != false,
              let audio = Self.httpsURL(audioURL) else { return nil }
        return Track(id: uuid, title: title, artistID: artistID, artistName: artistName,
                     audioURL: audio, artworkURL: Self.httpsURL(coverImageURL),
                     duration: duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
    }

    public static func httpsURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

public struct PublicCatalogPage: Decodable, Sendable {
    public let songs: [PublicCatalogSong]
    public let page: Int
    public let limit: Int

    /// Use the source count, before invalid/hidden tracks or other authors are removed.
    public var hasMore: Bool { limit > 0 && songs.count >= limit }
    public func tracks(artistID: String? = nil) -> [Track] {
        songs.compactMap(\.track).filter { artistID == nil || $0.artistID == artistID }
    }
}
