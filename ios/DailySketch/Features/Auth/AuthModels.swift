import Foundation

enum AuthState: Equatable, Sendable {
    case guest
    case authenticating
    case authenticated(session: AuthSession)
    case failed(message: String)
}

struct AuthSession: Equatable, Sendable {
    let accessToken: String
    let subject: String
    let displayName: String?
}

struct CurrentUserProfile: Equatable, Sendable {
    let id: UUID
    let username: String?
    let displayName: String
    let profileCompleted: Bool
    let status: String
}
