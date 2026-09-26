import Foundation
import NearFMCore

enum WalletIdentityVerification {
    /// Only this fixed mainnet RPC is trusted to bind an Ed25519 key to an account.
    private static let rpcURL = URL(string: "https://rpc.mainnet.fastnear.com")!

    static func accountID(callback: URL, challenge: WalletIdentityChallenge) async throws -> String {
        let proof = try challenge.verify(callbackURL: callback)
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": "dacha-identity", "method": "query",
            "params": ["request_type": "view_access_key", "finality": "final",
                       "account_id": proof.accountID, "public_key": proof.publicKey],
        ])
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: WalletRPCDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WalletIdentityError.unavailable
        }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == rpcURL.scheme, response.url?.host == rpcURL.host,
              response.url?.port == nil, ["", "/"].contains(response.url?.path ?? "invalid") else {
            throw WalletIdentityError.unavailable
        }
        try WalletIdentityProof.validateAccessKeyResponse(data)
        // Network verification must also finish within this attempt's lifetime.
        _ = try challenge.verify(callbackURL: callback)
        return proof.accountID
    }
}

private final class WalletRPCDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
