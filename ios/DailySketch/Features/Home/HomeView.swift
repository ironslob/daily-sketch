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
                    feedFetcher: dependencies.promptRepository
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

                promptSection(model)

                PrimaryButton(
                    title: "Start Sketch",
                    action: { model.startSketch() },
                    isDisabled: !model.canStartSketch
                )

                Text("Community Sketches")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)

                feedSection(model)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.lg)
        }
        .alert(
            "Sketch sessions are coming soon",
            isPresented: Binding(
                get: { model.showsStartSketchPlaceholder },
                set: { if !$0 { model.dismissStartSketchPlaceholder() } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.dismissStartSketchPlaceholder()
            }
        } message: {
            Text("Timer selection and sketch sessions arrive in the next update. Your prompt is ready when you are.")
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
