import SwiftUI

struct DeleteAccountView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var model: DeleteAccountViewModel?
    @State private var showsFinalConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text("Delete Account")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Your public profile will disappear. Submissions and images will be removed according to our deletion policy. Likes you made are removed and Reflections you wrote are deleted. This action may not be immediately reversible.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                if let error = model?.errorMessage {
                    Text(error)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.danger)
                }

                PrimaryButton(
                    title: "Continue",
                    action: { showsFinalConfirmation = true },
                    isDisabled: model?.isDeleting == true
                )

                SecondaryButton(title: "Keep my account") {
                    dismiss()
                }
            }
            .padding(AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.lg)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Permanently delete your account?",
            isPresented: $showsFinalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await model?.confirmDeletion()
                    if model?.didComplete == true {
                        dependencies.navigation.profilePath.removeAll()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This schedules account deletion and signs you out.")
        }
        .task {
            if model == nil {
                model = DeleteAccountViewModel(
                    accountDeleter: dependencies.accountDeleter,
                    auth: dependencies.auth,
                    draftStore: dependencies.draftStore,
                    draftImageStore: dependencies.draftImageStore
                )
            }
        }
    }
}
