import SwiftUI

struct ProfilePlaceholderView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.contentGapLarge) {
                if dependencies.auth.isAuthenticated, let user = dependencies.auth.currentUser {
                    authenticatedContent(user: user)
                } else {
                    guestContent
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dependencies.navigation.profilePath.append(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    @ViewBuilder
    private func authenticatedContent(user: CurrentUserProfile) -> some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(AppColors.primary)
            .accessibilityHidden(true)

        Text(user.displayName)
            .font(AppTypography.title2)
            .foregroundStyle(AppColors.textPrimary)
            .multilineTextAlignment(.center)

        Text(user.username.map { "@\($0)" } ?? "Username arrives in profile completion")
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)

        Text(user.profileCompleted ? "Profile complete" : "Profile incomplete")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .accessibilityLabel(user.profileCompleted ? "Profile complete" : "Profile incomplete")
    }

    @ViewBuilder
    private var guestContent: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 72))
            .foregroundStyle(AppColors.primary)
            .accessibilityHidden(true)

        Text("Keep your creative history")
            .font(AppTypography.title2)
            .foregroundStyle(AppColors.textPrimary)
            .multilineTextAlignment(.center)

        Text("Create a free account to save Submissions, streaks, Likes, and Reflections.")
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)

        PrimaryButton(title: "Create Free Account") {
            dependencies.navigation.profilePath.append(.authentication(.signUp))
        }
        .accessibilityLabel("Create Free Account")

        Button("Sign In") {
            dependencies.navigation.profilePath.append(.authentication(.signIn))
        }
        .font(AppTypography.headline)
        .foregroundStyle(AppColors.primary)
        .frame(minHeight: AppSpacing.minimumTouchTarget)
        .accessibilityLabel("Sign In")
    }
}

#Preview {
    NavigationStack {
        ProfilePlaceholderView()
    }
    .environment(AppDependencies.live)
}
