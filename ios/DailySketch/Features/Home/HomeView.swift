import SwiftUI

struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: HomeViewModel?
    @State private var showsDiscardDraftConfirmation = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingView(message: "Loading today’s inspiration…")
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Daily Sketch")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                let model = HomeViewModel(
                    promptFetcher: dependencies.promptRepository,
                    feedFetcher: dependencies.promptRepository,
                    socialService: dependencies.socialRepository,
                    publishedStore: dependencies.publishedSubmissionStore,
                    homeCacheStore: dependencies.homeCacheStore,
                    networkMonitor: dependencies.networkMonitor,
                    analytics: dependencies.analytics,
                    sketchFlow: dependencies.makeSketchFlowViewModel(),
                    isAuthenticated: { dependencies.auth.isAuthenticated },
                    accessTokenProvider: { dependencies.auth.accessToken }
                )
                viewModel = model
                await model.load()
            }
        }
        .onChange(of: dependencies.networkMonitor.isOnline) { _, _ in
            viewModel?.syncOfflineState()
        }
    }

    @ViewBuilder
    private func content(_ model: HomeViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.contentGapLarge) {
                Text("Today’s Inspiration")
                    .font(AppTypography.display)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Use all three words as inspiration for today’s sketch.")
                    .font(AppTypography.bodyLarge)
                    .foregroundStyle(AppColors.textSecondary)

                if let offlineMessage = model.offlineIndicatorMessage {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(AppColors.textSecondary)
                            .accessibilityHidden(true)
                        Text(offlineMessage)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(offlineMessage)
                }

                if model.isRefreshingPrompt {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refreshing prompt…")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .accessibilityLabel("Refreshing today’s prompt")
                }

                if model.sketchFlow.showsRecoveryBanner {
                    recoveryBanner(model)
                }

                if model.sketchFlow.changeTimerHintVisible {
                    changeTimerHint(model)
                }

                if let message = model.sketchFlow.syncBannerMessage {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                if let message = model.sketchFlow.draftSavedBanner {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.success)
                }

                promptSection(model)

                if model.hasSketchedToday {
                    sketchedTodaySection(model)
                }

                if model.sketchFlow.isCreatingSession {
                    LoadingView(message: "Starting your sketch…")
                }

                PrimaryButton(
                    title: model.primarySketchButtonTitle,
                    action: { model.startSketch() },
                    isDisabled: !model.canStartSketch || model.sketchFlow.isCreatingSession,
                    systemImage: model.hasSketchedToday ? "plus" : nil
                )
                .accessibilityHint(
                    model.hasSketchedToday
                        ? "Starts another sketch for today’s prompt"
                        : "Starts today’s timed sketch session"
                )

                if let draft = model.sketchFlow.recoverableDraft {
                    DraftCardView(
                        draft: draft,
                        thumbnail: model.sketchFlow.recoverableDraftThumbnail,
                        onContinue: { model.sketchFlow.reopenDraft(draft) },
                        onDiscard: { showsDiscardDraftConfirmation = true }
                    )
                }

                Text("Community Sketches")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)

                feedSection(model)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.lg)
        }
        .refreshable {
            await model.refresh()
        }
        .sheet(
            isPresented: Binding(
                get: { model.sketchFlow.showsTimerSelection },
                set: { if !$0 { model.sketchFlow.dismissTimerSelection() } }
            )
        ) {
            TimerSelectionView(
                selectedOption: Binding(
                    get: { model.sketchFlow.selectedTimerOption },
                    set: { model.sketchFlow.selectedTimerOption = $0 }
                ),
                rememberChoice: Binding(
                    get: { model.sketchFlow.rememberChoice },
                    set: { model.sketchFlow.rememberChoice = $0 }
                ),
                onStart: {
                    if let prompt = model.loadedPrompt {
                        model.sketchFlow.confirmTimerSelection(prompt: prompt)
                    }
                },
                onDismiss: { model.sketchFlow.dismissTimerSelection() },
                isStarting: model.sketchFlow.isCreatingSession
            )
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { model.sketchFlow.showsActiveSession },
                set: { if !$0 { model.sketchFlow.handleSessionEnded() } }
            )
        ) {
            if let sessionModel = model.sketchFlow.sessionViewModel {
                SketchSessionView(model: sessionModel)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { model.sketchFlow.showsCaptureSource },
                set: { if !$0 { model.sketchFlow.dismissCaptureSource() } }
            )
        ) {
            CaptureSourceView(
                cameraAuthorizer: model.sketchFlow.cameraAuthorizerForCapture,
                onImageData: { data in
                    model.sketchFlow.handleCapturedImageData(data)
                },
                onCancel: {
                    model.sketchFlow.dismissCaptureSource()
                },
                onValidationError: { message in
                    model.sketchFlow.handleCaptureValidationError(message)
                }
            )
            .overlay(alignment: .bottom) {
                if let message = model.sketchFlow.captureValidationMessage {
                    Text(message)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.danger)
                        .padding()
                        .background(AppColors.dangerSoft)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadii.medium, style: .continuous))
                        .padding()
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { model.sketchFlow.showsReviewSubmission },
                set: { newValue in
                    if !newValue, !model.sketchFlow.showsSaveYourCreativity, !model.sketchFlow.showsCaptureSource {
                        model.sketchFlow.handleReviewOutcome(.continueLater)
                    }
                }
            )
        ) {
            if let reviewModel = model.sketchFlow.reviewViewModel {
                ReviewSubmissionView(model: reviewModel)
                    .fullScreenCover(
                        isPresented: Binding(
                            get: { model.sketchFlow.showsSaveYourCreativity },
                            set: { if !$0 { model.sketchFlow.continueLaterFromCreativity() } }
                        )
                    ) {
                        SaveYourCreativityView(
                            thumbnail: reviewModel.previewImage,
                            onCreateAccount: { model.sketchFlow.presentCreateAccountFromCreativity() },
                            onSignIn: { model.sketchFlow.presentSignInFromCreativity() },
                            onContinueLater: { model.sketchFlow.continueLaterFromCreativity() }
                        )
                        .sheet(
                            isPresented: Binding(
                                get: { model.sketchFlow.showsAuthSheet },
                                set: { model.sketchFlow.showsAuthSheet = $0 }
                            )
                        ) {
                            NavigationStack {
                                AuthenticationView(mode: model.sketchFlow.authSheetMode)
                                    .toolbar {
                                        ToolbarItem(placement: .cancellationAction) {
                                            Button("Close") {
                                                model.sketchFlow.showsAuthSheet = false
                                            }
                                        }
                                    }
                            }
                            .environment(dependencies)
                            .onChange(of: dependencies.auth.isAuthenticated) { _, isAuthenticated in
                                if isAuthenticated {
                                    model.sketchFlow.handleAuthenticationCompleted()
                                }
                            }
                        }
                    }
            }
        }
        .onChange(of: model.sketchFlow.needsProfileCompletionPresentation) { _, needsPresentation in
            guard needsPresentation else { return }
            dependencies.navigation.resumePublicationAfterProfileCompletion = true
            dependencies.navigation.presentProfileCompletion(preferHome: true)
            model.sketchFlow.acknowledgeProfileCompletionPresentation()
        }
        .onChange(of: dependencies.navigation.publishResumeRequested) { _, requested in
            guard requested else { return }
            dependencies.navigation.publishResumeRequested = false
            model.sketchFlow.resumePendingPublishIfNeeded()
        }
        .onChange(of: model.sketchFlow.lastPublishedSubmissionId) { _, _ in
            model.refreshPublishedToday()
            Task { await model.retryFeed() }
        }
        .onChange(of: dependencies.navigation.feedNeedsRefresh) { _, needsRefresh in
            guard needsRefresh else { return }
            dependencies.navigation.feedNeedsRefresh = false
            Task { await model.retryFeed() }
        }
        .sheet(
            isPresented: Binding(
                get: { model.showsAuthSheet },
                set: { model.showsAuthSheet = $0 }
            )
        ) {
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
                    Task { await model.handleAuthenticationCompleted() }
                }
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
        .confirmationDialog(
            "Discard this draft?",
            isPresented: $showsDiscardDraftConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                model.sketchFlow.discardDraft()
            }
            Button("Keep Draft", role: .cancel) {}
        } message: {
            Text("This removes the local sketch image from this device.")
        }
    }

    private func sketchedTodaySection(_ model: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                    .accessibilityHidden(true)
                Text("You sketched today")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You sketched today")

            SecondaryButton(
                title: model.viewMySketchTitle,
                action: {
                    if let first = model.todaysPublished.first {
                        dependencies.navigation.homePath.append(.submissionDetail(first.id))
                    }
                }
            )
            .accessibilityHint("Opens your published sketch for today")
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadii.large, style: .continuous))
    }

    private func recoveryBanner(_ model: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("You have a sketch in progress")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            HStack(spacing: AppSpacing.contentGap) {
                PrimaryButton(
                    title: "Resume",
                    action: {
                        model.sketchFlow.resumeRecoverableSession { id in
                            if let loaded = model.loadedPrompt, loaded.id == id {
                                return loaded
                            }
                            return model.cachedPrompt
                        }
                    }
                )
                SecondaryButton(
                    title: "Discard",
                    action: { model.sketchFlow.discardRecoverableSession() }
                )
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadii.large, style: .continuous))
    }

    private func changeTimerHint(_ model: HomeViewModel) -> some View {
        HStack {
            Text("Using your remembered timer.")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Button("Change next time") {
                model.sketchFlow.changeTimerNextTime()
            }
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.primary)
        }
    }

    @ViewBuilder
    private func promptSection(_ model: HomeViewModel) -> some View {
        switch model.promptState {
        case .loading:
            VStack(alignment: .leading, spacing: AppSpacing.contentGap) {
                LoadingSkeleton(height: 72)
                HStack(spacing: AppSpacing.contentGap) {
                    LoadingSkeleton(height: 72)
                    LoadingSkeleton(height: 72)
                }
            }
            .accessibilityLabel("Loading today’s prompt")

        case .loaded(let prompt):
            PromptGroup(words: prompt.words, accessibilityLabel: prompt.accessibilityLabel)

        case .missing:
            ErrorStateView(
                title: "Today’s prompt isn’t ready",
                message: "Check back soon, or retry if you think this is temporary.",
                onRetry: { Task { await model.retryPrompt() } }
            )

        case .failed(let message):
            ErrorStateView(
                title: "Couldn’t load today’s prompt",
                message: message,
                onRetry: { Task { await model.retryPrompt() } }
            )
        }
    }

    @ViewBuilder
    private func feedSection(_ model: HomeViewModel) -> some View {
        switch model.feedState {
        case .loading:
            VStack(spacing: AppSpacing.contentGap) {
                LoadingSkeleton(height: 160)
                LoadingSkeleton(height: 160)
            }
            .accessibilityLabel("Loading community sketches")

        case .empty:
            EmptyStateView(
                title: "No sketches yet",
                message: "Be the first to share an interpretation of today’s prompt.",
                systemImage: "photo.on.rectangle.angled"
            )

        case .loaded(let items):
            LazyVStack(spacing: AppSpacing.contentGapLarge) {
                ForEach(items) { item in
                    SubmissionCard(
                        item: item,
                        onTapArtwork: {
                            dependencies.navigation.homePath.append(.submissionDetail(item.id))
                        },
                        onTapOwner: {
                            dependencies.navigation.homePath.append(.publicProfile(username: item.username))
                        },
                        onTapLike: {
                            Task { await model.toggleLike(itemId: item.id) }
                        },
                        onTapReflection: {
                            dependencies.navigation.homePath.append(.submissionDetail(item.id))
                        }
                    )
                    .onAppear {
                        Task { await model.loadMoreFeedIfNeeded(currentItem: item) }
                    }
                }

                if model.isLoadingMoreFeed {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .accessibilityLabel("Loading more sketches")
                }
            }

        case .failed(let message):
            ErrorStateView(
                title: "Couldn’t load community sketches",
                message: message,
                onRetry: { Task { await model.retryFeed() } }
            )
        }
    }
}

#Preview("Loading") {
    NavigationStack {
        HomeView()
    }
    .environment(AppDependencies.live)
}

#Preview("Dark") {
    NavigationStack {
        HomeView()
    }
    .environment(AppDependencies.live)
    .preferredColorScheme(.dark)
}
