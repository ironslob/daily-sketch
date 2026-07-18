import SwiftUI

struct RootTabView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var navigation = dependencies.navigation

        TabView {
            NavigationStack(path: $navigation.homePath) {
                HomeView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack(path: $navigation.profilePath) {
                ProfilePlaceholderView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem {
                Label("Profile", systemImage: "person")
            }
        }
        .tint(AppColors.primary)
        .onChange(of: dependencies.auth.needsProfileCompletion) { _, needsCompletion in
            guard needsCompletion else { return }
            if !dependencies.navigation.profilePath.contains(.profileCompletion) {
                dependencies.navigation.profilePath.append(.profileCompletion)
            }
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
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppDependencies.live)
}
