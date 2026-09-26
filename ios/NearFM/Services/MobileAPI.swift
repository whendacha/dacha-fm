import Foundation
import NearFMCore

struct TrackPage: Decodable {
    let tracks: [Track]
    let page: Int
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case tracks, page, hasMore = "has_more" }
}

struct ArtistPage: Decodable {
    let artists: [Artist]
    let page: Int
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case artists, page, hasMore = "has_more" }
}

struct MobileConfig: Decodable {
    let meteorEnabled: Bool
    let appleEnabled: Bool
    let privacyURL: URL?
    let supportURL: URL?
    enum CodingKeys: String, CodingKey {
        case meteorEnabled = "meteor_enabled", appleEnabled = "apple_enabled"
        case privacyURL = "privacy_url", supportURL = "support_url"
    }
}

struct MobileSession: Codable {
    let accessToken: String
    let userID: String
    var kind: String? = nil
    var isLocalWallet: Bool { kind == "verified-local-wallet" }
    var isCloudWallet: Bool { kind == "verified-cloud-wallet" }
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", userID = "user_id", kind }
}

enum MobileAPIError: LocalizedError {
    case unconfigured, insecureURL, invalidResponse, unauthorized, conflict, unavailable(String), server(Int, String)

    var errorDescription: String? {
        switch self {
        case .unconfigured, .insecureURL: "The service is temporarily unavailable. Please try again later."
        case .invalidResponse: "The server returned an invalid response."
        case .unauthorized: "Your session has expired. Please sign in again."
        case .conflict: "Your library changed on another device. Choose which version to keep."
        case .unavailable(let message): message
        case .server(let code, _): "The service is temporarily unavailable (\(code)). Please try again later."
        }
    }
}

struct MobileAPI {
    let baseURL: URL?
    var accessToken: String?
    private static let isolatedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: MobileAPIRedirectDelegate(), delegateQueue: nil)
    }()

    init(baseURL: URL?, accessToken: String? = nil) {
        self.baseURL = baseURL
        self.accessToken = accessToken
    }

    static func configuredURL(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$("), let url = URL(string: value) else { return nil }
        return url
    }

    private func endpoint(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard let baseURL else { throw MobileAPIError.unconfigured }
        guard (baseURL.scheme == "https" || Self.debugLocalhost(baseURL)),
              baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil else { throw MobileAPIError.insecureURL }
        guard var components = URLComponents(url: baseURL.appending(path: "api/mobile/v1/\(path)"), resolvingAgainstBaseURL: false) else {
            throw MobileAPIError.unconfigured
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw MobileAPIError.unconfigured }
        return url
    }

    private static func debugLocalhost(_ url: URL) -> Bool {
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")
        #else
        return false
        #endif
    }

    private func request<Response: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws -> Response {
        var request = URLRequest(url: try endpoint(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        if let accessToken, !accessToken.isEmpty { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await Self.isolatedSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MobileAPIError.invalidResponse }
        if response.statusCode == 401 { throw MobileAPIError.unauthorized }
        if response.statusCode == 409 { throw MobileAPIError.conflict }
        guard (200..<300).contains(response.statusCode) else {
            let message = String(data: data, encoding: .utf8).map { String($0.prefix(220)) } ?? "Unknown error"
            throw MobileAPIError.server(response.statusCode, message)
        }
        if data.isEmpty, let empty = EmptyResponse() as? Response { return empty }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw MobileAPIError.invalidResponse }
    }

    func config() async throws -> MobileConfig { try await request("config") }
    func tracks(query: String = "", artistID: String? = nil, page: Int = 1) async throws -> TrackPage {
        var items = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: "30")]
        if !query.isEmpty { items.append(.init(name: "q", value: query)) }
        if let artistID { items.append(.init(name: "artist_id", value: artistID)) }
        return try await request("tracks", query: items)
    }
    func artists(query: String = "", page: Int = 1) async throws -> ArtistPage {
        var items = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: "30")]
        if !query.isEmpty { items.append(.init(name: "q", value: query)) }
        return try await request("artists", query: items)
    }
    func library() async throws -> LibrarySnapshot { try await request("library") }
    func saveLibrary(_ snapshot: LibrarySnapshot) async throws -> LibrarySnapshot {
        try await request("library", method: "PUT", body: snapshot)
    }
    func report(trackID: String?, artistID: String?, reason: String) async throws {
        struct Report: Encodable {
            let trackID: String?; let artistID: String?; let reason: String
            enum CodingKeys: String, CodingKey { case trackID = "track_id", artistID = "artist_id", reason }
        }
        let _: EmptyResponse = try await request("reports", method: "POST", body: Report(trackID: trackID, artistID: artistID, reason: reason))
    }
    func appleLogin(identityToken: String, nonce: String, authorizationCode: String) async throws -> MobileSession {
        struct Body: Encodable { let identity_token: String; let nonce: String; let authorization_code: String }
        return try await request("auth/apple", method: "POST", body: Body(identity_token: identityToken, nonce: nonce, authorization_code: authorizationCode))
    }
    func meteorChallenge(codeChallenge: String) async throws -> MeteorChallenge {
        struct Body: Encodable { let code_challenge: String }
        return try await request("auth/meteor/challenge", method: "POST", body: Body(code_challenge: codeChallenge))
    }
    func meteorVerify(challengeID: String, accountID: String, publicKey: String, signature: String, verifier: String) async throws -> MobileSession {
        struct Body: Encodable {
            let challenge_id: String
            let account_id: String
            let public_key: String
            let signature: String
            let code_verifier: String
        }
        return try await request("auth/meteor/verify", method: "POST",
                                 body: Body(challenge_id: challengeID, account_id: accountID,
                                            public_key: publicKey, signature: signature, code_verifier: verifier))
    }
    func exchange(code: String, verifier: String) async throws -> MobileSession {
        struct Body: Encodable { let code: String; let code_verifier: String }
        return try await request("auth/exchange", method: "POST", body: Body(code: code, code_verifier: verifier))
    }
    func logout() async throws {
        let _: EmptyResponse = try await request("auth/logout", method: "POST")
    }
    func deleteAccount() async throws {
        let _: EmptyResponse = try await request("account", method: "DELETE")
    }
}

struct MeteorChallenge: Decodable {
    let id: String
    let message: String
    let nonce: [UInt8]
    let recipient: String
    let expiresAt: Date
    enum CodingKeys: String, CodingKey { case id, message, nonce, recipient, expiresAt = "expires_at" }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        message = try box.decode(String.self, forKey: .message)
        nonce = try box.decode([UInt8].self, forKey: .nonce)
        recipient = try box.decode(String.self, forKey: .recipient)
        let raw = try box.decode(String.self, forKey: .expiresAt)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { throw MobileAPIError.invalidResponse }
        expiresAt = date
    }
}

extension MobileAPI: LibraryRemote {
    func fetchLibrary() async throws -> LibrarySnapshot {
        do { return try await library() }
        catch MobileAPIError.unauthorized { throw LibrarySyncError.unauthorized }
        catch MobileAPIError.conflict { throw LibrarySyncError.conflict }
    }

    func putLibrary(_ snapshot: LibrarySnapshot) async throws -> LibrarySnapshot {
        do { return try await saveLibrary(snapshot) }
        catch MobileAPIError.unauthorized { throw LibrarySyncError.unauthorized }
        catch MobileAPIError.conflict { throw LibrarySyncError.conflict }
    }
}

private final class MobileAPIRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

private struct AnyEncodable: Encodable {
    let encodeBody: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeBody = value.encode }
    func encode(to encoder: Encoder) throws { try encodeBody(encoder) }
}
