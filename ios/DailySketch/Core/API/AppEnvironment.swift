import Foundation

enum DescopeConfig {
    /// Placeholder project ID used for local mock authentication.
    static let placeholderProjectID = "replace-me"

    /// True when the configured project ID is unset or still a template placeholder.
    static func isPlaceholderProjectID(_ projectID: String) -> Bool {
        let trimmed = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed == placeholderProjectID { return true }
        if trimmed.hasPrefix("replace-me") { return true }
        return false
    }
}

struct AppEnvironment: Equatable, Sendable {
    enum Kind: String, Sendable {
        case local
        case development
        case staging
        case production
    }

    let kind: Kind
    let apiBaseURL: URL
    let descopeProjectID: String

    static var current: AppEnvironment {
        let kindRaw = Bundle.main.object(forInfoDictionaryKey: "APP_ENVIRONMENT") as? String
            ?? ProcessInfo.processInfo.environment["APP_ENVIRONMENT"]
            ?? "local"
        let kind = Kind(rawValue: kindRaw) ?? .local

        let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? ProcessInfo.processInfo.environment["API_BASE_URL"]
            ?? "http://localhost:8000"

        guard let url = URL(string: urlString) else {
            preconditionFailure("Invalid API_BASE_URL: \(urlString)")
        }

        let descopeProjectID = Bundle.main.object(forInfoDictionaryKey: "DESCOPE_PROJECT_ID") as? String
            ?? ProcessInfo.processInfo.environment["DESCOPE_PROJECT_ID"]
            ?? DescopeConfig.placeholderProjectID

        return AppEnvironment(kind: kind, apiBaseURL: url, descopeProjectID: descopeProjectID)
    }
}
