import SwiftUI

struct RootTabView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var navigation = dependencies.navigation

        TabView(selection: $navigation.selectedTab) {
            NavigationStack(path: $navigation.homePath) {
                HomeView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route)
                    }
                    .overlay(alignment: .topTrailing) {
                        EnvironmentBadge(environment: AppEnvironment.current)
                            .padding(8)
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(AppTab.home)

            NavigationStack(path: $navigation.profilePath) {
                ProfileView(mode: .own)
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem {
                Label("Profile", systemImage: "person")
            }
            .tag(AppTab.profile)
        }
        .tint(AppColors.primary)
        .onChange(of: dependencies.auth.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task { await dependencies.hydrateUserPreferences() }
            }
        }
        .onChange(of: dependencies.auth.needsProfileCompletion) { _, needsCompletion in
            guard needsCompletion else { return }
            presentProfileCompletion()
        }
    }

    private func presentProfileCompletion() {
        if !dependencies.navigation.profilePath.contains(.profileCompletion) {
            dependencies.navigation.profilePath.append(.profileCompletion)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .settings:
            SettingsView()
        case .authentication(let mode):
            AuthenticationView(mode: mode)
        case .profileCompletion:
            ProfileCompletionView()
        case .submissionDetail(let submissionId):
            SubmissionDetailView(
                model: SubmissionDetailViewModel(
                    submissionId: submissionId,
                    submissionService: dependencies.submissionRepository,
                    socialService: dependencies.socialRepository,
                    safetyService: dependencies.safetyRepository,
                    isAuthenticated: { dependencies.auth.isAuthenticated },
                    accessTokenProvider: { dependencies.auth.accessToken },
                    analytics: dependencies.analytics,
                    onDeleted: {
                        dependencies.navigation.feedNeedsRefresh = true
                    },
                    onLikeChanged: { id, liked, count in
                        _ = (id, liked, count)
                        dependencies.navigation.feedNeedsRefresh = true
                    },
                    onBlockedUser: { _ in
                        dependencies.navigation.feedNeedsRefresh = true
                    }
                )
            )
        case .publicProfile(let username):
            ProfileView(mode: .other(username: username))
        case .editProfile:
            EditProfileView()
        case .blockedUsers:
            BlockedUsersView()
        case .deleteAccount:
            DeleteAccountView()
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppDependencies.live)
}
