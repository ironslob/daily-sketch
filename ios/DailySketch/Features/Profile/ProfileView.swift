import SwiftUI

struct ProfileView: View {
    @Environment(AppDependencies.self) private var dependencies
    let mode: ProfileViewModel.Mode
    @State private var model: ProfileViewModel?
    @State private var reportModel: ReportViewModel?
    @State private var showsBlockConfirmation = false
    @State private var showsAuthSheet = false
    @State private var authSheetMode: AuthenticationView.Mode = .signUp
    @State private var pendingProfileSafetyAction: ProfileSafetyAction?
    @State private var blockErrorMessage: String?

    private enum ProfileSafetyAction {
        case report
        case block
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                LoadingView(message: "Loading profile…")
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == .own {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dependencies.navigation.profilePath.append(.settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            } else if case .other = mode, let profile = model?.profile, !profile.isSelf {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            beginProfileReport(profile)
                        } label: {
                            Label("Report", systemImage: "exclamationmark.bubble")
                        }
                        Button {
                            beginProfileBlock(profile)
                        } label: {
                            Label("Block User", systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        .confirmationDialog(
            "Block this user?",
            isPresented: $showsBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Block User", role: .destructive) {
                Task { await confirmProfileBlock() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won’t see each other’s content. They won’t be notified.")
        }
        .sheet(isPresented: Binding(
            get: { reportModel != nil },
            set: { if !$0 { reportModel = nil } }
        )) {
            if let reportModel {
                ReportReasonSheet(model: reportModel) { _ in
                    showsBlockConfirmation = true
                }
            }
        }
        .sheet(isPresented: $showsAuthSheet) {
            NavigationStack {
                AuthenticationView(mode: authSheetMode)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showsAuthSheet = false }
                        }
                    }
            }
            .environment(dependencies)
            .onChange(of: dependencies.auth.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated, let profile = model?.profile {
                    showsAuthSheet = false
                    switch pendingProfileSafetyAction {
                    case .report:
                        pendingProfileSafetyAction = nil
                        presentReport(for: profile)
                    case .block:
                        pendingProfileSafetyAction = nil
                        showsBlockConfirmation = true
                    case .none:
                        break
                    }
                }
            }
        }
        .alert(
            "Couldn’t block user",
            isPresented: Binding(
                get: { blockErrorMessage != nil },
                set: { if !$0 { blockErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(blockErrorMessage ?? "")
        }
        .task(id: taskIdentity) {
            let next = ProfileViewModel(
                mode: mode,
                profileFetcher: dependencies.profileRepository,
                accessTokenProvider: { dependencies.auth.accessToken },
                ownUsernameProvider: { dependencies.auth.currentUser?.username },
                analytics: dependencies.analytics
            )
            model = next
            if shouldLoadProfile {
                await next.load()
            }
        }
        .refreshable {
            await model?.refresh()
        }
    }

    private var taskIdentity: String {
        switch mode {
        case .own:
            return "own-\(dependencies.auth.currentUser?.username ?? "none")-\(dependencies.auth.isAuthenticated)"
        case .other(let username):
            return "other-\(username)"
        }
    }

    private var shouldLoadProfile: Bool {
        switch mode {
        case .own:
            return dependencies.auth.isAuthenticated
                && (dependencies.auth.currentUser?.profileCompleted ?? false)
                && dependencies.auth.currentUser?.username != nil
        case .other:
            return true
        }
    }

    @ViewBuilder
    private func content(_ model: ProfileViewModel) -> some View {
        switch mode {
        case .own where !dependencies.auth.isAuthenticated:
            guestContent
        case .own where !(dependencies.auth.currentUser?.profileCompleted ?? false):
            incompleteOwnContent
        default:
            loadedOrLoadingContent(model)
        }
    }

    @ViewBuilder
    private func loadedOrLoadingContent(_ model: ProfileViewModel) -> some View {
        switch model.contentState {
        case .loading:
            LoadingView(message: "Loading profile…")
                .accessibilityLabel("Loading profile")
        case .failed(let message):
            ErrorStateView(
                title: "Couldn’t load this profile",
                message: message,
                onRetry: { Task { await model.load() } }
            )
        case .empty, .loaded:
            ScrollView {
                VStack(spacing: AppSpacing.contentGapLarge) {
                    if let profile = model.profile {
                        header(profile, model: model)
                    }
                    gallerySection(model)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.section)
            }
        }
    }

    private func header(_ profile: PublicProfileModel, model: ProfileViewModel) -> some View {
        VStack(spacing: AppSpacing.md) {
            AvatarView(
                displayName: profile.displayName,
                username: profile.username,
                avatarURL: profile.avatarURL,
                size: .profile
            )

            Text(profile.displayName)
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text("@\(profile.username)")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: AppSpacing.lg) {
                Label(model.streakLabel, systemImage: "flame")
                Label(model.submissionCountLabel, systemImage: "square.and.pencil")
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .accessibilityElement(children: .combine)

            if model.showsOwnControls {
                PrimaryButton(title: "Edit Profile") {
                    dependencies.navigation.profilePath.append(.editProfile)
                }
                .accessibilityLabel("Edit Profile")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func gallerySection(_ model: ProfileViewModel) -> some View {
        switch model.contentState {
        case .empty:
            if model.showsOwnControls {
                EmptyStateView(
                    title: "Your sketchbook starts here",
                    message: "Create your first response to today’s prompt.",
                    actionTitle: "Start Sketch",
                    action: {
                        dependencies.navigation.homePath = []
                    }
                )
            } else {
                EmptyStateView(
                    title: "No sketches shared yet.",
                    message: "This sketcher hasn’t published anything yet."
                )
            }
        case .loaded:
            LazyVStack(spacing: AppSpacing.contentGap) {
                ForEach(model.galleryItems) { item in
                    ProfileGalleryCard(item: item) {
                        appendDetail(item.id)
                    }
                    .onAppear {
                        Task { await model.loadMoreIfNeeded(currentItem: item) }
                    }
                }
                if model.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, AppSpacing.md)
                }
            }
        default:
            EmptyView()
        }
    }

    private func appendDetail(_ submissionId: UUID) {
        switch mode {
        case .own:
            dependencies.navigation.profilePath.append(.submissionDetail(submissionId))
        case .other:
            if !dependencies.navigation.homePath.isEmpty {
                dependencies.navigation.homePath.append(.submissionDetail(submissionId))
            } else {
                dependencies.navigation.profilePath.append(.submissionDetail(submissionId))
            }
        }
    }

    @ViewBuilder
    private var incompleteOwnContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.contentGapLarge) {
                AvatarView(
                    displayName: dependencies.auth.currentUser?.displayName ?? "Sketcher",
                    username: dependencies.auth.currentUser?.username ?? "sketcher",
                    avatarURL: dependencies.auth.currentUser?.avatarURL,
                    size: .profile
                )
                Text(dependencies.auth.currentUser?.displayName ?? "Sketcher")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Choose a username to complete your profile")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Complete Profile") {
                    dependencies.navigation.profilePath.append(.profileCompletion)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
    }

    @ViewBuilder
    private var guestContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.contentGapLarge) {
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
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
    }

    private func beginProfileReport(_ profile: PublicProfileModel) {
        guard dependencies.auth.isAuthenticated else {
            pendingProfileSafetyAction = .report
            authSheetMode = .signUp
            showsAuthSheet = true
            return
        }
        presentReport(for: profile)
    }

    private func beginProfileBlock(_ profile: PublicProfileModel) {
        guard dependencies.auth.isAuthenticated else {
            pendingProfileSafetyAction = .block
            authSheetMode = .signUp
            showsAuthSheet = true
            return
        }
        showsBlockConfirmation = true
    }

    private func presentReport(for profile: PublicProfileModel) {
        reportModel = ReportViewModel(
            targetType: .profile,
            targetId: profile.id,
            blockableUserId: profile.id,
            safetyService: dependencies.safetyRepository,
            accessTokenProvider: { dependencies.auth.accessToken }
        )
    }

    private func confirmProfileBlock() async {
        guard let profile = model?.profile else { return }
        guard let token = dependencies.auth.accessToken else { return }
        do {
            _ = try await dependencies.safetyRepository.blockUser(
                accessToken: token,
                userId: profile.id
            )
            dependencies.navigation.feedNeedsRefresh = true
            if !dependencies.navigation.homePath.isEmpty {
                dependencies.navigation.homePath.removeLast()
            } else if !dependencies.navigation.profilePath.isEmpty {
                dependencies.navigation.profilePath.removeLast()
            }
        } catch {
            blockErrorMessage = error.localizedDescription
        }
    }
}
