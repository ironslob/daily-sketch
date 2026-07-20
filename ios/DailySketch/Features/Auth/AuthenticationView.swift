import SwiftUI

struct AuthenticationView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var displayName = ""
    @State private var descopeFlowError: String?
    @State private var descopeFlowEpoch = 0
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
                    descopeContent
                }

                if let descopeFlowError {
                    ErrorStateView(
                        title: "Couldn’t sign in",
                        message: descopeFlowError,
                        onRetry: {
                            self.descopeFlowError = nil
                            descopeFlowEpoch += 1
                        }
                    )
                }

                if case .failed(let message) = dependencies.auth.state {
                    ErrorStateView(
                        title: "Couldn’t sign in",
                        message: message,
                        onRetry: {
                            Task { await retryMockAuth() }
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
                Task { await retryMockAuth() }
            }
            .accessibilityLabel(mode == .signUp ? "Create Free Account" : "Sign In")
        }
    }

    @ViewBuilder
    private var descopeContent: some View {
        VStack(spacing: AppSpacing.md) {
            Text(mode == .signUp
                ? "Continue with Descope to create your account."
                : "Continue with Descope to sign in.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            if let descope = dependencies.descopeAuthService {
                DescopeFlowHost(
                    projectID: descopeProjectID,
                    mode: mode,
                    flowEpoch: descopeFlowEpoch,
                    onFinished: { response in
                        let session = descope.complete(from: response)
                        Task {
                            await dependencies.auth.applyExternalSession(session)
                            finishAuthenticatedNavigation()
                        }
                    },
                    onCancelled: {
                        descopeFlowError = "Sign-in was cancelled. You can try again when you’re ready."
                    },
                    onFailed: { message in
                        descopeFlowError = message
                    }
                )
                .frame(minHeight: 420)
                .id(descopeFlowEpoch)
            }
        }
    }

    private var descopeProjectID: String {
        Bundle.main.object(forInfoDictionaryKey: "DESCOPE_PROJECT_ID") as? String ?? "replace-me"
    }

    private func retryMockAuth() async {
        guard dependencies.auth.usesMockAuthentication else { return }
        switch mode {
        case .signUp:
            await dependencies.auth.signUp(displayName: displayName)
        case .signIn:
            await dependencies.auth.signIn(displayName: displayName)
        }
        if dependencies.auth.isAuthenticated {
            finishAuthenticatedNavigation()
        }
    }

    private func finishAuthenticatedNavigation() {
        dependencies.navigation.profilePath.removeAll {
            $0 == .authentication(.signUp) || $0 == .authentication(.signIn)
        }
        dependencies.navigation.homePath.removeAll {
            $0 == .authentication(.signUp) || $0 == .authentication(.signIn)
        }
        if dependencies.auth.needsProfileCompletion {
            let preferHome = dependencies.navigation.resumePublicationAfterProfileCompletion
            dependencies.navigation.presentProfileCompletion(preferHome: preferHome)
        }
    }
}

#Preview {
    NavigationStack {
        AuthenticationView(mode: .signUp)
    }
    .environment(AppDependencies.live)
}
