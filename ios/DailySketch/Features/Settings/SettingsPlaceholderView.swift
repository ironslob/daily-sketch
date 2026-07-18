import SwiftUI

struct SettingsPlaceholderView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        List {
            Section("Account") {
                if dependencies.auth.isAuthenticated {
                    if let user = dependencies.auth.currentUser {
                        LabeledContent("Signed in as", value: user.displayName)
                    }
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await dependencies.auth.signOut()
                            dependencies.navigation.profilePath.removeAll()
                        }
                    }
                    .accessibilityLabel("Sign Out")
                } else {
                    Text("Browsing as guest")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Section("Sketch Preferences") {
                Text("Timer preference arrives in a later phase.")
                    .foregroundStyle(AppColors.textSecondary)
            }
            Section("Appearance") {
                Text("System / Light / Dark")
                    .foregroundStyle(AppColors.textSecondary)
            }
            Section("About") {
                LabeledContent("Version", value: "0.1.0")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsPlaceholderView()
    }
    .environment(AppDependencies.live)
}
