import DescopeKit
import Foundation

/// Descope-backed authentication used when a real project ID is configured.
@MainActor
final class DescopeAuthService: AuthServing {
    private let projectID: String

    init(projectID: String) {
        self.projectID = projectID
        Descope.setup(projectId: projectID)
    }

    var usesMockAuthentication: Bool { false }

    func restoreSession() async -> AuthSession? {
        guard let session = Descope.sessionManager.session, !session.refreshToken.isExpired else {
            return nil
        }
        return makeAuthSession(from: session)
    }

    func signUp(displayName: String) async throws -> AuthSession {
        throw AuthServiceError.notConfigured
    }

    func signIn(displayName: String) async throws -> AuthSession {
        throw AuthServiceError.notConfigured
    }

    func complete(from authResponse: AuthenticationResponse) -> AuthSession {
        let session = DescopeSession(from: authResponse)
        Descope.sessionManager.manageSession(session)
        return makeAuthSession(from: session)
    }

    func signOut() async {
        if let refreshJwt = Descope.sessionManager.session?.refreshJwt {
            try? await Descope.auth.revokeSessions(.currentSession, refreshJwt: refreshJwt)
        }
        Descope.sessionManager.clearSession()
    }

    func refreshIfNeeded(_ session: AuthSession) async throws -> AuthSession {
        try await Descope.sessionManager.refreshSessionIfNeeded()
        guard let managed = Descope.sessionManager.session else {
            throw AuthServiceError.sessionExpired
        }
        return makeAuthSession(from: managed)
    }

    private func makeAuthSession(from session: DescopeSession) -> AuthSession {
        AuthSession(
            accessToken: session.sessionJwt,
            subject: session.user.userId,
            displayName: session.user.name
        )
    }
}
