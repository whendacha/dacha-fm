import CryptoKit
import Foundation

public enum WalletIdentityError: Error, LocalizedError {
    case invalidChallenge, invalidCallback, expired, invalidSignature, unownedKey, unavailable

    public var errorDescription: String? {
        switch self {
        case .expired: "Время входа истекло. Откройте Meteor ещё раз."
        case .unavailable: "Не удалось проверить аккаунт Meteor. Проверьте подключение и попробуйте снова."
        default: "Данные входа Meteor не прошли проверку. Попробуйте снова."
        }
    }
}

/// An in-memory, single-attempt challenge with a fixed, explicit sign-in scope.
/// A proof alone does not create a service account or bearer token.
public struct WalletIdentityChallenge {
    public enum Scope { case local, cloud }
    public static let message = "Dacha FM sign-in\nVerify your Meteor account for the library on this device. No transaction or wallet permission is requested."
    public static let cloudMessage = "Dacha FM cloud sign-in\nSign in to sync your favorites and playlists across your devices. No transaction or wallet permission is requested."
    public let nonce: Data
    public let state: String
    public let recipient: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let scope: Scope
    public var signingMessage: String { scope == .cloud ? Self.cloudMessage : Self.message }
    private let bridgeURL: URL

    public init(bridgeURL: URL, nonce: Data, state: String, issuedAt: Date = Date(), scope: Scope = .local, expiresAt: Date? = nil) throws {
        let expiry = expiresAt ?? issuedAt.addingTimeInterval(300)
        guard bridgeURL.scheme == "https", let host = bridgeURL.host, !host.isEmpty,
              bridgeURL.user == nil, bridgeURL.password == nil, bridgeURL.port == nil,
              bridgeURL.query == nil, bridgeURL.fragment == nil,
              host.count <= 253, nonce.count == 32, Self.canonicalRandomString(state),
              expiry > issuedAt, expiry <= issuedAt.addingTimeInterval(300) else {
            throw WalletIdentityError.invalidChallenge
        }
        self.bridgeURL = bridgeURL
        self.nonce = nonce
        self.state = state
        self.recipient = host
        self.issuedAt = issuedAt
        self.expiresAt = expiry
        self.scope = scope
    }

    public func authorizationURL() throws -> URL {
        guard var components = URLComponents(url: bridgeURL.appending(path: "mobile/auth"), resolvingAgainstBaseURL: false) else {
            throw WalletIdentityError.invalidChallenge
        }
        components.queryItems = [
            .init(name: "mode", value: "identity"), .init(name: "state", value: state),
            .init(name: "nonce", value: Self.base64URL(nonce)), .init(name: "message", value: signingMessage),
            .init(name: "recipient", value: recipient),
        ]
        guard let url = components.url else { throw WalletIdentityError.invalidChallenge }
        return url
    }

    public func verify(callbackURL: URL, now: Date = Date()) throws -> WalletIdentityProof {
        guard now >= issuedAt, now <= expiresAt else { throw WalletIdentityError.expired }
        guard callbackURL.absoluteString.utf8.count <= 2048,
              let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              callback.scheme == "dachafm", callback.host == "auth", callback.path == "/callback",
              callback.user == nil, callback.password == nil, callback.port == nil, callback.query == nil,
              let fragment = callback.percentEncodedFragment,
              let items = URLComponents(string: "https://callback.invalid/?" + fragment)?.queryItems,
              items.count == 5 else { throw WalletIdentityError.invalidCallback }
        var values: [String: String] = [:]
        for item in items {
            guard let value = item.value, values[item.name] == nil else { throw WalletIdentityError.invalidCallback }
            values[item.name] = value
        }
        guard Set(values.keys) == Set(["mode", "state", "account_id", "public_key", "signature"]),
              values["mode"] == "identity", values["state"] == state,
              let account = values["account_id"], (2...64).contains(account.utf8.count),
              account.range(of: "^[a-z0-9]+(?:[._-][a-z0-9]+)*$", options: .regularExpression) != nil,
              let publicKey = values["public_key"], publicKey.hasPrefix("ed25519:"),
              let keyBytes = Self.decodeBase58(String(publicKey.dropFirst(8))), keyBytes.count == 32,
              let signatureString = values["signature"], signatureString.utf8.count == 88,
              let signature = Data(base64Encoded: signatureString), signature.count == 64,
              signature.base64EncodedString() == signatureString else { throw WalletIdentityError.invalidCallback }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
        guard key.isValidSignature(signature, for: signatureDigest()) else { throw WalletIdentityError.invalidSignature }
        return WalletIdentityProof(accountID: account, publicKey: publicKey, signature: signatureString)
    }

    private func signatureDigest() -> Data {
        var bytes = Data()
        func appendU32(_ value: UInt32) {
            bytes.append(contentsOf: [UInt8(value & 255), UInt8((value >> 8) & 255), UInt8((value >> 16) & 255), UInt8((value >> 24) & 255)])
        }
        func appendString(_ value: String) {
            let data = Data(value.utf8)
            appendU32(UInt32(data.count))
            bytes.append(data)
        }
        appendU32(2_147_484_061) // 2^31 + NEP-413; this payload cannot be a transaction.
        appendString(signingMessage)
        bytes.append(nonce) // Fixed [u8; 32], without a Borsh length prefix.
        appendString(recipient)
        bytes.append(0) // Optional callback URL is absent in the Meteor signMessage call.
        return Data(SHA256.hash(data: bytes))
    }

    private static func canonicalRandomString(_ value: String) -> Bool {
        guard value.utf8.count == 43, value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              let bytes = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="),
              bytes.count == 32 else { return false }
        return base64URL(bytes) == value
    }

    private static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase58(_ value: String) -> Data? {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
        guard (1...44).contains(value.utf8.count) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 1)
        for character in value.utf8 {
            guard let digit = alphabet.firstIndex(of: character) else { return nil }
            var carry = digit
            for index in bytes.indices.reversed() {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 255)
                carry >>= 8
            }
            while carry > 0 { bytes.insert(UInt8(carry & 255), at: 0); carry >>= 8 }
            guard bytes.count <= 32 else { return nil }
        }
        let zeros = value.utf8.prefix(while: { $0 == 49 }).count
        return Data(repeating: 0, count: zeros) + Data(bytes.drop(while: { $0 == 0 }))
    }
}

public struct WalletIdentityProof {
    public let accountID: String
    public let publicKey: String
    public let signature: String

    public static func validateAccessKeyResponse(_ data: Data) throws {
        guard data.count <= 128 * 1024,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["jsonrpc"] as? String == "2.0", json["id"] as? String == "dacha-identity",
              json["error"] == nil, let result = json["result"] as? [String: Any],
              result["permission"] as? String == "FullAccess" else { throw WalletIdentityError.unownedKey }
    }
}
