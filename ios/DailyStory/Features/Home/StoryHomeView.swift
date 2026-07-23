import SwiftUI

struct StoryHomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: StoryHomeViewModel?
    @State private var storyFlow: StoryFlowViewModel?

    var body: some View {
        Group {
            if let viewModel, let storyFlow {
                content(viewModel, storyFlow)
            } else {
                LoadingView(message: "Loading today’s inspiration…")
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(ProductConfig.current.homeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                let flow = dependencies.makeStoryFlowViewModel {
                    viewModel?.refreshPublishedToday()
                }
                storyFlow = flow
                let model = StoryHomeViewModel(
                    promptFetcher: dependencies.promptRepository,
                    feedFetcher: dependencies.promptRepository,
                    socialService: dependencies.socialRepository,
                    publishedStore: dependencies.publishedSubmissionStore,
                    homeCacheStore: dependencies.homeCacheStore,
                    networkMonitor: dependencies.networkMonitor,
                    analytics: dependencies.analytics,
                    isAuthenticated: { dependencies.auth.isAuthenticated },
                    accessTokenProvider: { dependencies.auth.accessToken }
                )
                viewModel = model
                flow.prepareOnAppear()
                await model.load()
            }
        }
        .onChange(of: dependencies.networkMonitor.isOnline) { _, _ in
            viewModel?.syncOfflineState()
        }
    }

    @ViewBuilder
    private func content(_ model: StoryHomeViewModel, _ flow: StoryFlowViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                inspirationSection(model, flow)
                communitySection(model)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.section)
        }
        .refreshable {
            await model.refresh()
        }
        .sheet(
            isPresented: Binding(
                get: { flow.showsTimerSelection },
                set: { if !$0 { flow.dismissTimerSelection() } }
            )
        ) {
            TimerSelectionView(
                selectedOption: Binding(
                    get: { flow.selectedTimerOption },
                    set: { flow.selectedTimerOption = $0 }
                ),
                rememberChoice: Binding(
                    get: { flow.rememberChoice },
                    set: { flow.rememberChoice = $0 }
                ),
                onStart: {
                    if let prompt = model.loadedPrompt {
                        flow.confirmTimerSelection(prompt: prompt)
                    }
                },
                onDismiss: { flow.dismissTimerSelection() },
                isStarting: flow.isCreatingSession
            )
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { flow.showsActiveSession },
                set: { if !$0 { flow.handleSessionEnded() } }
            )
        ) {
            if let sessionModel = flow.sessionViewModel {
                StorySessionView(model: sessionModel)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { flow.showsWritingEditor },
                set: { flow.showsWritingEditor = $0 }
            )
        ) {
            StoryWritingView(
                text: Binding(
                    get: { flow.draftText },
                    set: { flow.draftText = $0 }
                ),
                promptWords: flow.promptWords,
                wordCount: flow.wordCount,
                onPublish: { flow.submitStory() },
                onSaveDraft: { flow.saveDraft() },
                isPublishing: flow.isPublishing
            )
        }
        .sheet(
            isPresented: Binding(
                get: { flow.showsAuthSheet },
                set: { flow.showsAuthSheet = $0 }
            )
        ) {
            NavigationStack {
                AuthenticationView(mode: flow.authSheetMode)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { flow.showsAuthSheet = false }
                        }
                    }
            }
            .environment(dependencies)
        }
        .onChange(of: flow.lastPublishedSubmissionId) { _, _ in
            model.refreshPublishedToday()
            Task { await model.retryFeed() }
        }
        .onChange(of: dependencies.navigation.feedNeedsRefresh) { _, needsRefresh in
            guard needsRefresh else { return }
            dependencies.navigation.feedNeedsRefresh = false
            Task { await model.retryFeed() }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { flow.errorMessage != nil },
                set: { if !$0 { flow.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(flow.errorMessage ?? "")
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
    }

    private func inspirationSection(_ model: StoryHomeViewModel, _ flow: StoryFlowViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.contentGapLarge) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Today’s Inspiration")
                    .font(AppTypography.display)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Tap a prompt to start writing your daily story.")
                    .font(AppTypography.bodyLarge)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if let offlineMessage = model.offlineIndicatorMessage {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(AppColors.textSecondary)
                        .accessibilityHidden(true)
                    Text(offlineMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            if let banner = flow.draftSavedBanner {
                Text(banner)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.success)
            }

            promptSection(model)

            if model.hasPublishedToday {
                publishedTodaySection(model)
            }

            if flow.isCreatingSession {
                LoadingView(message: "Starting your story…")
            }

            PrimaryButton(
                title: model.hasPublishedToday ? "Write Another Story" : ProductConfig.current.startActionTitle,
                action: {
                    if let prompt = model.loadedPrompt {
                        flow.startWriting(prompt: prompt)
                    }
                },
                isDisabled: model.loadedPrompt == nil || flow.isCreatingSession,
                systemImage: model.hasPublishedToday ? "plus" : "pencil"
            )
            .accessibilityHint("Starts today’s timed writing session")
        }
    }

    private func publishedTodaySection(_ model: StoryHomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                    .accessibilityHidden(true)
                Text("You wrote today")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
            }

            SecondaryButton(
                title: model.todaysPublished.count > 1 ? "View My Stories" : "View My Story",
                action: {
                    if let first = model.todaysPublished.first {
                        dependencies.navigation.homePath.append(.submissionDetail(first.id))
                    }
                }
            )
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadii.large, style: .continuous))
    }

    private func communitySection(_ model: StoryHomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.contentGap) {
            Text(ProductConfig.current.communityTitle)
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)

            feedSection(model)
        }
    }

    @ViewBuilder
    private func promptSection(_ model: StoryHomeViewModel) -> some View {
        switch model.promptState {
        case .loading:
            LoadingSkeleton(height: PromptCardStackLayout.height)
                .accessibilityLabel("Loading today’s prompt")
        case .loaded(let prompt):
            PromptCardStack(words: prompt.words, accessibilityLabel: prompt.accessibilityLabel)
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
    private func feedSection(_ model: StoryHomeViewModel) -> some View {
        switch model.feedState {
        case .loading:
            VStack(spacing: AppSpacing.contentGap) {
                LoadingSkeleton(height: 160)
                LoadingSkeleton(height: 160)
            }
        case .empty:
            EmptyStateView(
                title: "No stories yet",
                message: "Be the first to share an interpretation of today’s prompt.",
                systemImage: "text.alignleft"
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
                }
            }
        case .failed(let message):
            ErrorStateView(
                title: "Couldn’t load community stories",
                message: message,
                onRetry: { Task { await model.retryFeed() } }
            )
        }
    }
}
