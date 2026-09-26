import CryptoKit
import Foundation
import XCTest
@testable import NearFMCore

final class WalletIdentityTests: XCTestCase {
    private let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let privateKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(0..<32))

    private func challenge(nonce: Data = Data(0..<32), recipient: String = "dacha.example", scope: WalletIdentityChallenge.Scope = .local) throws -> WalletIdentityChallenge {
        try WalletIdentityChallenge(bridgeURL: URL(string: "https://\(recipient)")!, nonce: nonce,
                                    state: String(repeating: "A", count: 43), issuedAt: issuedAt, scope: scope)
    }

    // Independent NEP-413 payload construction: u32 tag, Borsh strings,
    // the fixed-size nonce and the absent callback URL option.
    private func signedCallback(_ challenge: WalletIdentityChallenge, message: String? = nil,
                                state: String? = nil, signature: String? = nil) throws -> URL {
        var bytes = Data([0x9d, 0x01, 0x00, 0x80])
        for (index, field) in [Data((message ?? challenge.signingMessage).utf8), challenge.nonce, Data(challenge.recipient.utf8)].enumerated() {
            if index != 1 {
                let n = UInt32(field.count)
                bytes.append(contentsOf: [UInt8(n & 255), UInt8((n >> 8) & 255), UInt8((n >> 16) & 255), UInt8((n >> 24) & 255)])
            }
            bytes.append(field)
        }
        bytes.append(0)
        let signed = try privateKey.signature(for: Data(SHA256.hash(data: bytes)))
        var fragment = URLComponents()
        fragment.queryItems = [
            .init(name: "mode", value: "identity"),
            .init(name: "state", value: state ?? challenge.state),
            .init(name: "account_id", value: "listener.near"),
            .init(name: "public_key", value: "ed25519:" + encodeBase58(privateKey.publicKey.rawRepresentation)),
            .init(name: "signature", value: signature ?? signed.base64EncodedString()),
        ]
        var callback = URLComponents(string: "dachafm://auth/callback")!
        callback.percentEncodedFragment = fragment.percentEncodedQuery
        return callback.url!
    }

    func testValidSignatureAndRequestContainTheOriginalChallenge() throws {
        let c = try challenge()
        let url = try c.authorizationURL()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(url.path, "/mobile/auth")
        XCTAssertEqual(items.first { $0.name == "message" }?.value, WalletIdentityChallenge.message)
        XCTAssertEqual(items.first { $0.name == "nonce" }?.value, "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
        let proof = try c.verify(callbackURL: signedCallback(c), now: issuedAt.addingTimeInterval(10))
        XCTAssertEqual(proof.accountID, "listener.near")
        XCTAssertEqual(proof.publicKey, "ed25519:" + encodeBase58(privateKey.publicKey.rawRepresentation))
    }

    func testSignatureCannotBeReusedWithAnotherNonceMessageOrRecipient() throws {
        let original = try challenge()
        let callback = try signedCallback(original)
        XCTAssertThrowsError(try challenge(nonce: Data(repeating: 7, count: 32)).verify(callbackURL: callback, now: issuedAt))
        XCTAssertThrowsError(try challenge(recipient: "attacker.example").verify(callbackURL: callback, now: issuedAt))
        XCTAssertThrowsError(try original.verify(callbackURL: signedCallback(original, message: "different message"), now: issuedAt))
    }

    func testCloudAndLocalProofsCannotBeSubstitutedEvenWithSameNonceAndState() throws {
        let local = try challenge()
        let cloud = try challenge(scope: .cloud)
        XCTAssertEqual(cloud.signingMessage, "Dacha FM cloud sign-in\nSign in to sync your favorites and playlists across your devices. No transaction or wallet permission is requested.")
        let url = try cloud.authorizationURL()
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "message" }?.value, WalletIdentityChallenge.cloudMessage)
        let cloudCallback = try signedCallback(cloud)
        let proof = try cloud.verify(callbackURL: cloudCallback, now: issuedAt)
        XCTAssertEqual(Data(base64Encoded: proof.signature)?.count, 64)
        XCTAssertThrowsError(try local.verify(callbackURL: cloudCallback, now: issuedAt))
        XCTAssertThrowsError(try cloud.verify(callbackURL: signedCallback(local), now: issuedAt))
    }

    func testCloudChallengeHonorsEarlierServerExpiry() throws {
        let c = try WalletIdentityChallenge(bridgeURL: URL(string: "https://dacha.example")!, nonce: Data(0..<32),
                                            state: String(repeating: "A", count: 43), issuedAt: issuedAt,
                                            scope: .cloud, expiresAt: issuedAt.addingTimeInterval(90))
        XCTAssertNoThrow(try c.verify(callbackURL: signedCallback(c), now: issuedAt.addingTimeInterval(30)))
        XCTAssertThrowsError(try c.verify(callbackURL: signedCallback(c), now: issuedAt.addingTimeInterval(91)))
        XCTAssertThrowsError(try WalletIdentityChallenge(bridgeURL: URL(string: "https://dacha.example")!, nonce: Data(0..<32),
                                                          state: c.state, issuedAt: issuedAt, scope: .cloud, expiresAt: issuedAt.addingTimeInterval(-1)))
    }

    func testCloudProofMatchesIndependentNodeCryptoVector() throws {
        // Independently serialized with Node Buffer + node:crypto Ed25519.
        // Public test seed 00...1f, never a real wallet key.
        let c = try challenge(recipient: "whendacha.github.io", scope: .cloud)
        let signature = "ainyqYZSvwUW5UU8TAtMf/9qYI7GdQcCEpycmPP7MpwpTvp58Og2O3LwhxXUiILLy6mfaSvqmZo/YopxVgcDBg=="
        let proof = try c.verify(callbackURL: signedCallback(c, signature: signature), now: issuedAt)
        XCTAssertEqual(proof.publicKey, "ed25519:FAe4sisG95oZ42w7buUn5qEE4TAnfTTFPiguZUHmhiF")
        XCTAssertEqual(proof.signature, signature)
    }

    func testStateExpiryAndDuplicateParametersFailClosed() throws {
        let c = try challenge()
        XCTAssertThrowsError(try c.verify(callbackURL: signedCallback(c, state: String(repeating: "B", count: 43)), now: issuedAt))
        XCTAssertThrowsError(try c.verify(callbackURL: signedCallback(c), now: issuedAt.addingTimeInterval(301)))
        XCTAssertThrowsError(try c.verify(callbackURL: signedCallback(c), now: issuedAt.addingTimeInterval(-1)))
        let duplicate = URL(string: try signedCallback(c).absoluteString + "&account_id=other.near")!
        XCTAssertThrowsError(try c.verify(callbackURL: duplicate, now: issuedAt))
        let queryInstead = URL(string: try signedCallback(c).absoluteString.replacingOccurrences(of: "#", with: "?"))!
        XCTAssertThrowsError(try c.verify(callbackURL: queryInstead, now: issuedAt))
    }

    func testMalformedProofAndNonHTTPSOriginAreRejected() throws {
        let c = try challenge()
        XCTAssertThrowsError(try c.verify(callbackURL: signedCallback(c, signature: String(repeating: "A", count: 20000)), now: issuedAt))
        let badKey = URL(string: try signedCallback(c).absoluteString.replacingOccurrences(of: "ed25519:", with: "secp256k1:"))!
        XCTAssertThrowsError(try c.verify(callbackURL: badKey, now: issuedAt))
        XCTAssertThrowsError(try WalletIdentityChallenge(bridgeURL: URL(string: "http://dacha.example")!, nonce: Data(0..<32), state: c.state, issuedAt: issuedAt))
        XCTAssertThrowsError(try WalletIdentityChallenge(bridgeURL: URL(string: "https://user@dacha.example")!, nonce: Data(0..<32), state: c.state, issuedAt: issuedAt))
    }

    func testRPCRequiresFullAccessAndRejectsErrorsAndFunctionCallKeys() throws {
        XCTAssertNoThrow(try WalletIdentityProof.validateAccessKeyResponse(Data(#"{"jsonrpc":"2.0","id":"dacha-identity","result":{"permission":"FullAccess","nonce":1}}"#.utf8)))
        XCTAssertThrowsError(try WalletIdentityProof.validateAccessKeyResponse(Data(#"{"result":{"permission":{"FunctionCall":{"receiver_id":"listener.near"}}}}"#.utf8)))
        XCTAssertThrowsError(try WalletIdentityProof.validateAccessKeyResponse(Data(#"{"error":{"code":-32000},"result":{"permission":"FullAccess"}}"#.utf8)))
        XCTAssertThrowsError(try WalletIdentityProof.validateAccessKeyResponse(Data(#"{"result":{}}"#.utf8)))
    }

    private func encodeBase58(_ data: Data) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var digits = [Int](repeating: 0, count: 1)
        for byte in data {
            var carry = Int(byte)
            for i in digits.indices {
                carry += digits[i] * 256
                digits[i] = carry % 58
                carry /= 58
            }
            while carry > 0 { digits.append(carry % 58); carry /= 58 }
        }
        return String(repeating: "1", count: data.prefix(while: { $0 == 0 }).count) + String(digits.reversed().map { alphabet[$0] })
    }
}
