import SwiftUI

struct SubmissionDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Bindable private var model: SubmissionDetailViewModel
    @State private var showsDeleteConfirmation = false
    @State private var showsBlockConfirmation = false
    @State private var reportModel: ReportViewModel?
    @State private var pendingBlockUserId: UUID?
    @State private var reflectionPendingDelete: ReflectionModel?
    @State private var shareItems: [Any] = []
    @State private var showsShareSheet = false
    @State private var isPreparingShare = false

    init(model: SubmissionDetailViewModel) {
        self.model = model
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                LoadingView(message: "Loading sketch…")
                    .accessibilityLabel("Loading submission")

            case .failed(let message):
                ErrorStateView(
                    title: "Couldn’t load this sketch",
                    message: message,
                    onRetry: { Task { await model.load() } }
                )

            case .deleted:
                EmptyStateView(
                    title: model.didBlockAuthor ? "User blocked" : "Sketch deleted",
                    message: model.didBlockAuthor
                        ? "Their content no longer appears in your feed."
                        : "This submission is no longer available."
                )

            case .loaded(let submission):
                loadedContent(submission)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(model.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu
            }
        }
        .confirmationDialog(
            "Delete this sketch?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Sketch", role: .destructive) {
                Task {
                    await model.deleteSubmission()
                    if case .deleted = model.state {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your sketch from the community feed and your profile.")
        }
        .confirmationDialog(
            "Block this user?",
            isPresented: $showsBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Block User", role: .destructive) {
                if let userId = pendingBlockUserId {
                    Task {
                        await model.blockAuthor(userId: userId)
                        if model.didBlockAuthor {
                            dismiss()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won’t see each other’s content. They won’t be notified.")
        }
        .confirmationDialog(
            "Delete this reflection?",
            isPresented: Binding(
                get: { reflectionPendingDelete != nil },
                set: { if !$0 { reflectionPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Reflection", role: .destructive) {
                if let reflection = reflectionPendingDelete {
                    Task { await model.deleteReflection(reflection) }
                }
                reflectionPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                reflectionPendingDelete = nil
            }
        }
        .alert(
            "Couldn’t update Like",
            isPresented: Binding(
                get: { model.likeErrorMessage != nil },
                set: { if !$0 { model.clearLikeError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.likeErrorMessage ?? "")
        }
        .alert(
            "Couldn’t block user",
            isPresented: Binding(
                get: { model.blockErrorMessage != nil },
                set: { if !$0 { model.clearBlockError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.blockErrorMessage ?? "")
        }
        .sheet(isPresented: $model.showsAuthSheet) {
            NavigationStack {
                AuthenticationView(mode: model.authSheetMode)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                model.showsAuthSheet = false
                            }
                        }
                    }
            }
            .environment(dependencies)
            .onChange(of: dependencies.auth.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    Task {
                        await model.handleAuthenticationCompleted()
                        presentPendingSafetyActionIfNeeded()
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { reportModel != nil },
            set: { if !$0 { reportModel = nil } }
        )) {
            if let reportModel {
                ReportReasonSheet(model: reportModel) { userId in
                    pendingBlockUserId = userId
                    showsBlockConfirmation = true
                }
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            ActivityShareSheet(activityItems: shareItems)
        }
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var overflowMenu: some View {
        Menu {
            Button {
                Task { await prepareShare() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(isPreparingShare)

            if model.isOwner {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete Submission", systemImage: "trash")
                }
                .disabled(model.isDeleting)
            } else if case .loaded(let submission) = model.state {
                Button {
                    beginReport(
                        targetType: .submission,
                        targetId: submission.id,
                        blockableUserId: submission.userId
                    )
                } label: {
                    Label("Report", systemImage: "exclamationmark.bubble")
                }
                Button {
                    beginBlock(userId: submission.userId)
                } label: {
                    Label("Block User", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(minWidth: AppSpacing.minimumTouchTarget, minHeight: AppSpacing.minimumTouchTarget)
        }
        .accessibilityLabel("More actions")
    }

    private func loadedContent(_ submission: SubmissionModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.contentGapLarge) {
                artwork(submission)
                ownerRow(submission)
                FlowPromptChips(words: submission.promptWords)

                HStack(spacing: AppSpacing.md) {
                    Label(model.timerLabel, systemImage: "timer")
                    Text("•")
                        .accessibilityHidden(true)
                    Label(model.promptDateLabel, systemImage: "calendar")
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .accessibilityElement(children: .combine)

                if let caption = submission.caption, !caption.isEmpty {
                    Text(caption)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityLabel("Caption: \(caption)")
                }

                Divider()
                    .overlay(AppColors.divider)

                socialRow(submission)

                reflectionsSection(submission)

                if let deleteErrorMessage = model.deleteErrorMessage {
                    Text(deleteErrorMessage)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.danger)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.lg)
        }
    }

    private func artwork(_ submission: SubmissionModel) -> some View {
        AsyncImage(url: submission.imageURL) { phase in
            switch phase {
            case .empty:
                LoadingSkeleton(height: 320)
                    .accessibilityLabel("Loading artwork")
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(
                        RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
                    )
                    .accessibilityLabel(artworkLabel(for: submission))
            case .failure:
                RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
                    .fill(AppColors.surfaceTertiary)
                    .frame(height: 280)
                    .overlay {
                        Text("Couldn’t load image")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textTertiary)
                    }
            @unknown default:
                EmptyView()
            }
        }
    }

    private func ownerRow(_ submission: SubmissionModel) -> some View {
        Button {
            dependencies.navigation.homePath.append(
                .publicProfile(username: submission.username)
            )
        } label: {
            HStack(spacing: AppSpacing.sm) {
                AvatarView(
                    displayName: submission.displayName,
                    username: submission.username,
                    size: .detail
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(submission.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("@\(submission.username)")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textTertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(submission.displayName), @\(submission.username)")
        .accessibilityHint("Opens profile")
    }

    private func socialRow(_ submission: SubmissionModel) -> some View {
        HStack(spacing: AppSpacing.xl) {
            SocialActionButton(
                kind: .like,
                count: submission.likeCount,
                isActive: submission.viewerHasLiked,
                isDisabled: model.isLikeInFlight,
                action: {
                    Task { await model.toggleLike() }
                }
            )
            SocialActionButton(
                kind: .reflection,
                count: submission.reflectionCount,
                action: {}
            )
            SocialActionButton(
                kind: .share,
                usesLabel: true,
                action: {
                    Task { await prepareShare() }
                }
            )
            Spacer()
        }
    }

    private func prepareShare() async {
        guard case .loaded(let submission) = model.state, !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        let image = await SubmissionImageDownloader.downloadImage(from: submission.imageURL)
        let payload = SubmissionSharePayload.make(
            promptWords: submission.promptWords,
            displayName: submission.displayName,
            username: submission.username,
            image: image,
            publicLink: nil
        )
        shareItems = payload.activityItems
        showsShareSheet = true
    }

    @ViewBuilder
    private func reflectionsSection(_ submission: SubmissionModel) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.contentGap) {
            Text("Reflections")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)

            switch model.reflectionsState {
            case .loading:
                LoadingView(message: "Loading reflections…")
                    .accessibilityLabel("Loading reflections")

            case .failed(let message):
                ErrorStateView(
                    title: "Couldn’t load reflections",
                    message: message,
                    onRetry: { Task { await model.loadReflections(reset: true) } }
                )

            case .loaded:
                if model.reflections.isEmpty {
                    EmptyStateView(
                        title: "No reflections yet",
                        message: "Share a kind thought.",
                        systemImage: "bubble.left"
                    )
                } else {
                    ForEach(model.reflections) { reflection in
                        ReflectionRow(
                            reflection: reflection,
                            onDelete: reflection.isAuthor ? { reflectionPendingDelete = reflection } : nil,
                            onReport: reflection.isAuthor
                                ? nil
                                : {
                                    beginReport(
                                        targetType: .reflection,
                                        targetId: reflection.id,
                                        blockableUserId: reflection.userId
                                    )
                                }
                        )
                        .onAppear {
                            Task { await model.loadMoreReflectionsIfNeeded(currentItem: reflection) }
                        }
                    }
                }
            }

            composer
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                AvatarView(
                    displayName: dependencies.auth.currentUser?.displayName ?? "You",
                    username: dependencies.auth.currentUser?.username ?? "you",
                    size: .feed
                )
                TextField("Add a reflection…", text: $model.composerText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(AppSpacing.sm)
                    .background(AppColors.surfaceTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadii.medium, style: .continuous))
                    .accessibilityLabel("Add a reflection")
            }

            HStack {
                if model.composerText.count > SubmissionDetailViewModel.reflectionMaxLength - 40 {
                    Text("\(model.remainingReflectionCharacters)")
                        .font(AppTypography.caption)
                        .foregroundStyle(
                            model.remainingReflectionCharacters < 0
                                ? AppColors.danger
                                : AppColors.textTertiary
                        )
                }
                Spacer()
                Button {
                    Task { await model.postReflection() }
                } label: {
                    if model.isPostingReflection {
                        ProgressView()
                    } else {
                        Text("Post")
                            .font(AppTypography.headline)
                    }
                }
                .disabled(!model.canPostReflection)
                .foregroundStyle(
                    model.canPostReflection ? AppColors.primary : AppColors.textTertiary
                )
                .accessibilityLabel("Post reflection")
            }

            if let reflectionErrorMessage = model.reflectionErrorMessage {
                Text(reflectionErrorMessage)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.danger)
            }
        }
    }

    private func artworkLabel(for submission: SubmissionModel) -> String {
        if let caption = submission.caption, !caption.isEmpty {
            return "Sketch by \(submission.displayName). \(caption)"
        }
        return "Sketch by \(submission.displayName). Prompt: \(submission.promptWords.joined(separator: ", "))"
    }

    private func beginReport(
        targetType: ReportTargetKind,
        targetId: UUID,
        blockableUserId: UUID?
    ) {
        if !dependencies.auth.isAuthenticated {
            switch targetType {
            case .submission:
                model.requestReportSubmission()
            case .reflection:
                model.requestReportReflection(targetId)
            case .profile:
                break
            }
            return
        }
        reportModel = ReportViewModel(
            targetType: targetType,
            targetId: targetId,
            blockableUserId: blockableUserId,
            safetyService: dependencies.safetyRepository,
            accessTokenProvider: { dependencies.auth.accessToken }
        )
    }

    private func beginBlock(userId: UUID) {
        if !dependencies.auth.isAuthenticated {
            model.requestBlockAuthor()
            return
        }
        pendingBlockUserId = userId
        showsBlockConfirmation = true
    }

    private func presentPendingSafetyActionIfNeeded() {
        guard let pending = model.consumePendingSafetyAction() else { return }
        guard case .loaded(let submission) = model.state else { return }
        switch pending {
        case .reportSubmission:
            reportModel = ReportViewModel(
                targetType: .submission,
                targetId: submission.id,
                blockableUserId: submission.userId,
                safetyService: dependencies.safetyRepository,
                accessTokenProvider: { dependencies.auth.accessToken }
            )
        case .blockAuthor:
            pendingBlockUserId = submission.userId
            showsBlockConfirmation = true
        case .reportReflection(let reflectionId):
            let authorId = model.reflections.first(where: { $0.id == reflectionId })?.userId
            reportModel = ReportViewModel(
                targetType: .reflection,
                targetId: reflectionId,
                blockableUserId: authorId,
                safetyService: dependencies.safetyRepository,
                accessTokenProvider: { dependencies.auth.accessToken }
            )
        case .like, .postReflection:
            break
        }
    }
}

private struct FlowPromptChips: View {
    let words: [String]

    var body: some View {
        FlexibleChipRow(words: words)
    }
}

private struct FlexibleChipRow: View {
    let words: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(words, id: \.self) { word in
                    PromptChip(word: word)
                }
            }
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(words, id: \.self) { word in
                    PromptChip(word: word)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prompt: \(words.joined(separator: ", "))")
    }
}

#Preview("Loading") {
    NavigationStack {
        SubmissionDetailView(
            model: SubmissionDetailViewModel(
                submissionId: UUID(),
                submissionService: RecordingSubmissionRepository(),
                socialService: RecordingSocialRepository(),
                accessTokenProvider: { nil }
            )
        )
    }
    .environment(AppDependencies.live)
}

#Preview("Dark") {
    NavigationStack {
        SubmissionDetailView(
            model: SubmissionDetailViewModel(
                submissionId: UUID(),
                submissionService: {
                    let repo = RecordingSubmissionRepository()
                    repo.nextSubmission = SubmissionModel(
                        id: UUID(),
                        caption: "Quiet lines.",
                        status: "published",
                        timerMode: "countdown",
                        timerSeconds: 300,
                        likeCount: 0,
                        reflectionCount: 0,
                        viewerHasLiked: false,
                        isOwner: true,
                        imageURL: URL(string: "https://example.test/display")!,
                        thumbnailURL: URL(string: "https://example.test/thumb")!,
                        userId: UUID(),
                        username: "sketchy",
                        displayName: "Sketcher",
                        promptWords: ["Chocolate", "Coffee", "Banana"],
                        promptDate: Date(),
                        sketchSessionId: UUID(),
                        publishedAt: Date()
                    )
                    return repo
                }(),
                socialService: RecordingSocialRepository(),
                accessTokenProvider: { "token" }
            )
        )
    }
    .environment(AppDependencies.live)
    .preferredColorScheme(.dark)
}
