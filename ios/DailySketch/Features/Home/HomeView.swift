import SwiftUI

struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: HomeViewModel?

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
                    sketchFlow: dependencies.makeSketchFlowViewModel()
                )
                viewModel = model
                await model.load()
            }
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

                promptSection(model)

                if model.sketchFlow.isCreatingSession {
                    LoadingView(message: "Starting your sketch…")
                }

                PrimaryButton(
                    title: "Start Sketch",
                    action: { model.startSketch() },
                    isDisabled: !model.canStartSketch || model.sketchFlow.isCreatingSession
                )

                Text("Community Sketches")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)

                feedSection(model)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.lg)
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
