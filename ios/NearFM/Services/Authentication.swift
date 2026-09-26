import AuthenticationServices
import CryptoKit
import Foundation
import NearFMCore
import Security
import UIKit

enum AuthenticationError: LocalizedError {
    case cancelled, missingCredential, invalidCallback, unconfiguredBridge, insecureBridge
    var errorDescription: String? {
        switch self {
        case .cancelled: "Вход отменён."
        case .missingCredential: "Apple не вернула данные для входа. Попробуйте ещё раз."
        case .invalidCallback: "Ответ входа не прошёл проверку. Попробуйте ещё раз."
        case .unconfiguredBridge, .insecureBridge: "Вход через Meteor временно недоступен. Попробуйте позже."
        }
    }
}

enum SessionKeychain {
    private static let key = "mobile-listener-session"
    private static let service = "\(Bundle.main.bundleIdentifier ?? "com.whendacha.dachafm").listener"

    static func load() -> MobileSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(MobileSession.self, from: data)
    }

    static func save(_ session: MobileSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func clear() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class AuthenticationService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
    private var appleContinuation: CheckedContinuation<(String, String), Error>?
    private var appleController: ASAuthorizationController?
    private var webSession: ASWebAuthenticationSession?
    private var cloudSignInPending = false

    func signInWithApple(api: MobileAPI) async throws -> MobileSession {
        let nonce = Self.randomURLSafeString()
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = []
        request.nonce = Self.sha256Hex(nonce)
        let credential = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(String, String), Error>) in
            appleContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            appleController = controller
            controller.performRequests()
        }
        return try await api.appleLogin(identityToken: credential.0, nonce: nonce, authorizationCode: credential.1)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let continuation = appleContinuation else { return }
        appleContinuation = nil
        appleController = nil
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
              let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) else {
            continuation.resume(throwing: AuthenticationError.missingCredential)
            return
        }
        continuation.resume(returning: (token, code))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let continuation = appleContinuation else { return }
        appleContinuation = nil
        appleController = nil
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            continuation.resume(throwing: AuthenticationError.cancelled)
        } else {
            continuation.resume(throwing: error)
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor() }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor() }

    private func anchor() -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow } ?? UIWindow()
    }

    /// Verifies a Meteor identity for the device's local library only.
    /// No backend session or cloud account is created by this flow.
    func meteorIdentity(bridgeURL: URL) async throws -> String {
        guard webSession == nil, !cloudSignInPending else { throw AuthenticationError.invalidCallback }
        var nonce = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce) == errSecSuccess else {
            throw AuthenticationError.invalidCallback
        }
        let challenge = try WalletIdentityChallenge(bridgeURL: bridgeURL, nonce: Data(nonce), state: Self.randomURLSafeString())
        let url = try challenge.authorizationURL()
        let callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "dachafm") { [weak self] callback, error in
                Task { @MainActor in self?.webSession = nil }
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthenticationError.cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: AuthenticationError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            // Allow an existing Meteor browser session to be reused on this device.
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start() {
                webSession = nil
                continuation.resume(throwing: AuthenticationError.unconfiguredBridge)
            }
        }
        return try await WalletIdentityVerification.accountID(callback: callback, challenge: challenge)
    }

    /// The server owns the one-use nonce; the PKCE verifier remains native and
    /// is sent only to the configured cloud API after the wallet proof is checked.
    func signInWithMeteorCloud(api: MobileAPI, bridgeURL: URL?) async throws -> MobileSession {
        guard let bridgeURL else { throw AuthenticationError.unconfiguredBridge }
        guard webSession == nil, !cloudSignInPending else { throw AuthenticationError.invalidCallback }
        cloudSignInPending = true
        defer { cloudSignInPending = false }
        let verifier = Self.randomURLSafeString(length: 64)
        let codeChallenge = Self.sha256Data(verifier).base64URLEncodedString()
        let server = try await api.meteorChallenge(codeChallenge: codeChallenge)
        let issuedAt = Date()
        guard UUID(uuidString: server.id) != nil,
              server.message == WalletIdentityChallenge.cloudMessage,
              server.recipient == bridgeURL.host,
              server.nonce.count == 32,
              server.expiresAt > issuedAt,
              server.expiresAt <= issuedAt.addingTimeInterval(330) else {
            throw AuthenticationError.invalidCallback
        }
        let challenge = try WalletIdentityChallenge(bridgeURL: bridgeURL, nonce: Data(server.nonce),
                                                     state: Self.randomURLSafeString(), issuedAt: issuedAt,
                                                     scope: .cloud, expiresAt: min(server.expiresAt, issuedAt.addingTimeInterval(300)))
        let url = try challenge.authorizationURL()
        let callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "dachafm") { [weak self] callback, error in
                Task { @MainActor in
                    self?.webSession = nil
                    if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(throwing: AuthenticationError.cancelled)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else if let callback {
                        continuation.resume(returning: callback)
                    } else {
                        continuation.resume(throwing: AuthenticationError.invalidCallback)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start() {
                webSession = nil
                continuation.resume(throwing: AuthenticationError.unconfiguredBridge)
            }
        }
        let proof = try challenge.verify(callbackURL: callback)
        let session = try await api.meteorVerify(challengeID: server.id, accountID: proof.accountID,
                                                publicKey: proof.publicKey, signature: proof.signature, verifier: verifier)
        guard session.kind == "verified-cloud-wallet", session.userID == proof.accountID,
              session.accessToken.utf8.count == 43,
              session.accessToken.range(of: "^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$", options: .regularExpression) != nil else {
            throw AuthenticationError.invalidCallback
        }
        return session
    }

    func signInWithMeteor(api: MobileAPI, bridgeURL: URL?) async throws -> MobileSession {
        guard let bridgeURL else { throw AuthenticationError.unconfiguredBridge }
        guard bridgeURL.scheme == "https" || Self.debugLocalhost(bridgeURL) else { throw AuthenticationError.insecureBridge }
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.sha256Data(verifier).base64URLEncodedString()
        let state = Self.randomURLSafeString()
        guard var components = URLComponents(url: bridgeURL.appending(path: "mobile/auth"), resolvingAgainstBaseURL: false) else {
            throw AuthenticationError.unconfiguredBridge
        }
        components.queryItems = [URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "state", value: state)]
        guard let url = components.url else { throw AuthenticationError.unconfiguredBridge }
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "dachafm") { [weak self] callback, error in
                Task { @MainActor in self?.webSession = nil }
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin { continuation.resume(throwing: AuthenticationError.cancelled) }
                else if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: AuthenticationError.invalidCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webSession = session
            if !session.start() {
                webSession = nil
                continuation.resume(throwing: AuthenticationError.unconfiguredBridge)
            }
        }
        guard callbackURL.scheme == "dachafm", callbackURL.host == "auth", callbackURL.path == "/callback",
              let result = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              result.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = result.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw AuthenticationError.invalidCallback
        }
        return try await api.exchange(code: code, verifier: verifier)
    }

    private static func randomURLSafeString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess)
        return Data(bytes).base64URLEncodedString()
    }
    private static func sha256Hex(_ text: String) -> String {
        sha256Data(text).map { String(format: "%02x", $0) }.joined()
    }
    private static func sha256Data(_ text: String) -> Data { Data(SHA256.hash(data: Data(text.utf8))) }
    private static func debugLocalhost(_ url: URL) -> Bool {
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")
        #else
        return false
        #endif
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
