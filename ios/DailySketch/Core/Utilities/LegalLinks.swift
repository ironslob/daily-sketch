import Foundation

enum LegalLinks {
    static var support: URL? { url(for: "SUPPORT_URL") }
    static var privacy: URL? { url(for: "PRIVACY_URL") }
    static var terms: URL? { url(for: "TERMS_URL") }
    static var communityGuidelines: URL? { url(for: "COMMUNITY_GUIDELINES_URL") }

    private static func url(for key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
