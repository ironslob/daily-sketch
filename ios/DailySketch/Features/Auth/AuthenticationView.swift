import SwiftUI

struct AuthenticationView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var displayName = ""
    var mode: Mode = .signUp

    enum Mode: Hashable {
        case signUp
        case signIn
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.contentGapLarge) {
                Text("Daily Sketch")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                if dependencies.auth.usesMockAuthentication {
                    mockAuthContent
                } else {
                    descopePlaceholder
                }

                if case .failed(let message) = dependencies.auth.state {
                    ErrorStateView(
                        title: "Couldn’t sign in",
                        message: message,
                        onRetry: {
                            Task { await retry() }
                        }
                    )
                }

                if case .authenticating = dependencies.auth.state {
                    LoadingView(message: "Signing in…")
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(mode == .signUp ? "Create Account" : "Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .disabled({
            if case .authenticating = dependencies.auth.state { return true }
            return false
        }())
    }

    private var subtitle: String {
        switch mode {
        case .signUp:
            return "Create a free account to save sketches, build your history, and join the community."
        case .signIn:
            return "Welcome back. Sign in to continue your creative journal."
        }
    }

    @ViewBuilder
    private var mockAuthContent: some View {
        VStack(spacing: AppSpacing.md) {
            TextField("Display name (optional)", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Display name")

            Text("Local mock authentication is active because DESCOPE_PROJECT_ID is unset.")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            PrimaryButton(title: mode == .signUp ? "Create Free Account" : "Sign In") {
                Task { await retry() }
            }
            .accessibilityLabel(mode == .signUp ? "Create Free Account" : "Sign In")
        }
    }

    @ViewBuilder
    private var descopePlaceholder: some View {
        VStack(spacing: AppSpacing.md) {
            Text("Descope project \(descopeProjectID) is configured. Present a hosted Descope Flow from this screen in a follow-up when flow URLs are available.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            if let descope = dependencies.descopeAuthService {
                DescopeFlowHost(projectID: descopeProjectID) { response in
                    let session = descope.complete(from: response)
                    Task {
                        await dependencies.auth.applyExternalSession(session)
                    }
                }
            }
        }
    }

    private var descopeProjectID: String {
        Bundle.main.object(forInfoDictionaryKey: "DESCOPE_PROJECT_ID") as? String ?? "replace-me"
    }

    private func retry() async {
        switch mode {
        case .signUp:
            await dependencies.auth.signUp(displayName: displayName)
        case .signIn:
            await dependencies.auth.signIn(displayName: displayName)
        }
        if dependencies.auth.isAuthenticated {
            dependencies.navigation.profilePath.removeAll { $0 == .authentication(.signUp) || $0 == .authentication(.signIn) }
        }
    }
}

#Preview {
    NavigationStack {
        AuthenticationView(mode: .signUp)
    }
    .environment(AppDependencies.live)
}
