import SwiftUI

struct BlockedUsersView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: BlockedUsersViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                LoadingView(message: "Loading blocked users…")
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Blocked Users")
        .task {
            if model == nil {
                let viewModel = BlockedUsersViewModel(
                    safetyService: dependencies.safetyRepository,
                    accessTokenProvider: { dependencies.auth.accessToken }
                )
                model = viewModel
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: BlockedUsersViewModel) -> some View {
        switch model.state {
        case .loading:
            LoadingView(message: "Loading blocked users…")
        case .empty:
            EmptyStateView(
                title: "No blocked users.",
                message: "People you block will appear here.",
                systemImage: "hand.raised"
            )
        case .failed(let message):
            ErrorStateView(
                title: "Couldn’t load blocked users",
                message: message,
                onRetry: { Task { await model.load() } }
            )
        case .loaded:
            List {
                ForEach(model.users) { user in
                    HStack(spacing: AppSpacing.sm) {
                        AvatarView(displayName: user.displayName, username: user.username, size: .feed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(AppTypography.headline)
                            Text("@\(user.username)")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Button("Unblock") {
                            Task { await model.unblock(user) }
                        }
                        .accessibilityLabel("Unblock \(user.displayName)")
                    }
                    .listRowBackground(AppColors.surfaceSecondary)
                }
                if let actionError = model.actionError {
                    Text(actionError)
                        .foregroundStyle(AppColors.danger)
                        .font(AppTypography.caption)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}
