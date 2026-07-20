import SwiftUI

struct EnvironmentBadge: View {
    let environment: AppEnvironment

    var body: some View {
        if shouldShow {
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Environment \(label)")
        }
    }

    private var shouldShow: Bool {
        let flag = Bundle.main.object(forInfoDictionaryKey: "SHOW_ENVIRONMENT_BADGE") as? String
        if flag == "NO" { return false }
        return environment.kind != .production
    }

    private var label: String {
        switch environment.kind {
        case .local: "Local"
        case .development: "Development"
        case .staging: "Staging"
        case .production: "Production"
        }
    }
}
