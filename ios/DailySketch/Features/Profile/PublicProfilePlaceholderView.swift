import SwiftUI

/// Lightweight public-profile placeholder until Phase 10.
struct PublicProfilePlaceholderView: View {
    let username: String

    var body: some View {
        VStack(spacing: AppSpacing.contentGap) {
            AvatarView(displayName: username, username: username, size: .profile)

            Text("@\(username)")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)

            Text("Public profiles and sketch journals arrive in a later update.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.screenHorizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Public profile for @\(username). Coming soon.")
    }
}

#Preview("Light") {
    NavigationStack {
        PublicProfilePlaceholderView(username: "alexdraws")
    }
}

#Preview("Dark") {
    NavigationStack {
        PublicProfilePlaceholderView(username: "sketchy_matt")
    }
    .preferredColorScheme(.dark)
}
