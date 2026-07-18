import SwiftUI

struct RootTabView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var navigation = dependencies.navigation

        TabView {
            NavigationStack(path: $navigation.homePath) {
                HomePlaceholderView()
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
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .settings:
            SettingsPlaceholderView()
        case .authentication(let mode):
            AuthenticationView(mode: mode)
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppDependencies.live)
}
