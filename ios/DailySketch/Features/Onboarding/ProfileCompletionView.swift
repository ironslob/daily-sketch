import SwiftUI

struct ProfileCompletionView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: ProfileCompletionViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingView(message: "Loading…")
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Complete Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel == nil {
                viewModel = ProfileCompletionViewModel(
                    auth: dependencies.auth,
                    preferencesService: dependencies.preferencesService,
                    reminderSync: dependencies.reminderSync,
                    analytics: dependencies.analytics
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: ProfileCompletionViewModel) -> some View {
        @Bindable var model = viewModel
        ScrollView {
            VStack(spacing: AppSpacing.contentGapLarge) {
                Text("Choose how you appear")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                Text("Pick a unique username and display name. You can add a photo later from Edit Profile.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                avatarPlaceholder

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Username")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    TextField("username", text: $model.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Username")
                        .onChange(of: model.username) { _, _ in
                            model.validateUsernameLive()
                        }
                    if let hint = model.usernameHint {
                        Text(hint)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)
                            .accessibilityLabel(hint)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Display name")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    TextField("Display name", text: $model.displayName)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Display name")
                }

                Toggle(isOn: $model.enableReminder) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily reminder")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Optional. You can change this later in Settings.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .tint(AppColors.primary)
                .accessibilityLabel("Daily reminder")

                if let error = model.errorMessage {
                    ErrorStateView(
                        title: "Couldn’t save profile",
                        message: error,
                        onRetry: {
                            Task { await save(model) }
                        }
                    )
                }

                if model.isSaving {
                    LoadingView(message: "Saving…")
                }

                PrimaryButton(title: "Save and Continue", action: {
                    Task { await save(model) }
                }, isDisabled: !model.canSave)
                .accessibilityLabel("Save and Continue")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
    }

    private var avatarPlaceholder: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.primary)
                .accessibilityHidden(true)
            Text("Photo optional — add one anytime in Edit Profile after saving.")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photo optional. Add one anytime in Edit Profile after saving.")
    }

    private func save(_ model: ProfileCompletionViewModel) async {
        let success = await model.save()
        if success {
            let shouldResumePublish = dependencies.navigation.resumePublicationAfterProfileCompletion
            dependencies.navigation.dismissProfileCompletion()
            if shouldResumePublish {
                dependencies.navigation.resumePublicationAfterProfileCompletion = false
                dependencies.navigation.selectedTab = .home
                dependencies.navigation.publishResumeRequested = true
            }
        }
    }
}

#Preview("Normal") {
    NavigationStack {
        ProfileCompletionView()
    }
    .environment(AppDependencies.live)
}

#Preview("Dark") {
    NavigationStack {
        ProfileCompletionView()
    }
    .environment(AppDependencies.live)
    .preferredColorScheme(.dark)
}
