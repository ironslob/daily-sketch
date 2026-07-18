import Foundation
@preconcurrency import DailySketchAPI

protocol MeFetching: Sendable {
    func fetchMe(accessToken: String) async throws -> CurrentUserProfile
}

struct MeRepository: MeFetching {
    let baseURL: URL

    func fetchMe(accessToken: String) async throws -> CurrentUserProfile {
        var base = baseURL.absoluteString
        if base.hasSuffix("/") {
            base.removeLast()
        }
        DailySketchAPIAPI.basePath = base
        DailySketchAPIAPI.customHeaders["Authorization"] = "Bearer \(accessToken)"
        DailySketchAPITokenBridge.setBearerToken(accessToken)

        do {
            let user = try await MeAPI.getMe()
            return CurrentUserProfile(
                id: user.id,
                username: user.username,
                displayName: user.displayName,
                profileCompleted: user.profileCompleted,
                status: user.status.rawValue
            )
        } catch {
            throw mapAPIError(error)
        }
    }

    private func mapAPIError(_ error: Error) -> Error {
        if let errorResponse = error as? ErrorResponse {
            switch errorResponse {
            case .error(let code, _, _, _):
                if code == 401 {
                    return AuthServiceError.sessionExpired
                }
            }
        }
        return AuthServiceError.underlying(error.localizedDescription)
    }
}

/// Test double that records the bearer token used for authenticated requests.
final class RecordingMeFetcher: MeFetching, @unchecked Sendable {
    private(set) var lastAccessToken: String?
    var profile: CurrentUserProfile
    var error: Error?

    init(profile: CurrentUserProfile) {
        self.profile = profile
    }

    func fetchMe(accessToken: String) async throws -> CurrentUserProfile {
        lastAccessToken = accessToken
        DailySketchAPITokenBridge.setBearerToken(accessToken)
        if let error {
            throw error
        }
        return profile
    }
}
