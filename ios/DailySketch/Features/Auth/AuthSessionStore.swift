import Foundation
import Observation
@preconcurrency import DailySketchAPI

@MainActor
@Observable
final class AuthSessionStore {
    private(set) var state: AuthState = .guest
    private(set) var currentUser: CurrentUserProfile?

    private let authService: any AuthServing
    private let meFetcher: any MeFetching

    init(authService: any AuthServing, meFetcher: any MeFetching) {
        self.authService = authService
        self.meFetcher = meFetcher
    }

    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    var usesMockAuthentication: Bool {
        authService.usesMockAuthentication
    }

    func bootstrap() async {
        guard let session = await authService.restoreSession() else {
            state = .guest
            currentUser = nil
            return
        }
        await applyAuthenticated(session: session)
    }

    func signUp(displayName: String) async {
        await authenticate {
            try await authService.signUp(displayName: displayName)
        }
    }

    func signIn(displayName: String) async {
        await authenticate {
            try await authService.signIn(displayName: displayName)
        }
    }

    func applyExternalSession(_ session: AuthSession) async {
        await applyAuthenticated(session: session)
    }

    func signOut() async {
        await authService.signOut()
        currentUser = nil
        state = .guest
        DailySketchAPITokenBridge.clear()
    }

    func handleExpiredSession() async {
        await authService.signOut()
        currentUser = nil
        DailySketchAPITokenBridge.clear()
        state = .failed(message: AuthServiceError.sessionExpired.localizedDescription)
    }

    private func authenticate(perform: () async throws -> AuthSession) async {
        state = .authenticating
        do {
            let session = try await perform()
            await applyAuthenticated(session: session)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(message: message)
        }
    }

    private func applyAuthenticated(session: AuthSession) async {
        state = .authenticating
        do {
            let refreshed = try await authService.refreshIfNeeded(session)
            let profile = try await meFetcher.fetchMe(accessToken: refreshed.accessToken)
            currentUser = profile
            state = .authenticated(session: refreshed)
        } catch {
            await authService.signOut()
            currentUser = nil
            DailySketchAPITokenBridge.clear()
            if let authError = error as? AuthServiceError, authError == .sessionExpired {
                state = .failed(message: AuthServiceError.sessionExpired.localizedDescription)
            } else {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                state = .failed(message: message)
            }
        }
    }
}

enum DailySketchAPITokenBridge {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _token: String?

    static func setBearerToken(_ token: String) {
        lock.lock()
        _token = token
        lock.unlock()
    }

    static func clear() {
        lock.lock()
        _token = nil
        lock.unlock()
        DailySketchAPIAPI.customHeaders.removeValue(forKey: "Authorization")
    }

    static var currentToken: String? {
        lock.lock()
        defer { lock.unlock() }
        return _token
    }
}
