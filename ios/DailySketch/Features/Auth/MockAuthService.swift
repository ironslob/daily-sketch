import CryptoKit
import Foundation

/// Local mock auth used when `DESCOPE_PROJECT_ID` is the placeholder `replace-me`.
/// Mints HS256 JWTs accepted by the backend LocalDevTokenVerifier.
final class MockAuthService: AuthServing {
    static let jwtSecret = "daily-sketch-local-dev-only-secret!!" // pragma: allowlist secret
    static let issuer = "daily-sketch-local"
    static let audience = "daily-sketch-local"

    private let keychainAccount = "mock.auth.session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var usesMockAuthentication: Bool { true }

    func restoreSession() async -> AuthSession? {
        guard let data = try? KeychainStore.load(account: keychainAccount),
              let stored = try? decoder.decode(StoredSession.self, from: data)
        else {
            return nil
        }
        if isExpired(token: stored.accessToken) {
            KeychainStore.delete(account: keychainAccount)
            return nil
        }
        return AuthSession(
            accessToken: stored.accessToken,
            subject: stored.subject,
            displayName: stored.displayName
        )
    }

    func signUp(displayName: String) async throws -> AuthSession {
        try await mintAndPersist(displayName: displayName.isEmpty ? "New sketcher" : displayName)
    }

    func signIn(displayName: String) async throws -> AuthSession {
        try await mintAndPersist(displayName: displayName.isEmpty ? "Returning sketcher" : displayName)
    }

    func signOut() async {
        KeychainStore.delete(account: keychainAccount)
    }

    func refreshIfNeeded(_ session: AuthSession) async throws -> AuthSession {
        if isExpired(token: session.accessToken) {
            throw AuthServiceError.sessionExpired
        }
        return session
    }

    private func mintAndPersist(displayName: String) async throws -> AuthSession {
        let subject = "local|\(UUID().uuidString)"
        let token = try Self.mintToken(subject: subject, name: displayName)
        let session = AuthSession(accessToken: token, subject: subject, displayName: displayName)
        let stored = StoredSession(accessToken: token, subject: subject, displayName: displayName)
        let data = try encoder.encode(stored)
        try KeychainStore.save(account: keychainAccount, data: data)
        return session
    }

    static func mintToken(subject: String, name: String, expiresIn: TimeInterval = 60 * 60 * 24 * 7) throws -> String {
        let header = base64URL(["alg": "HS256", "typ": "JWT"])
        let now = Int(Date().timeIntervalSince1970)
        let payload = base64URL([
            "sub": subject,
            "name": name,
            "iss": issuer,
            "aud": audience,
            "iat": now,
            "exp": now + Int(expiresIn),
        ] as [String: Any])
        let signingInput = "\(header).\(payload)"
        let key = SymmetricKey(data: Data(jwtSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
        let sig = Data(signature).base64URLEncodedString()
        return "\(signingInput).\(sig)"
    }

    private func isExpired(token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = json["exp"] as? Int
        else {
            return true
        }
        return Date().timeIntervalSince1970 >= Double(exp)
    }

    private static func base64URL(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.base64URLEncodedString()
    }
}

private struct StoredSession: Codable {
    let accessToken: String
    let subject: String
    let displayName: String?
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }
}
