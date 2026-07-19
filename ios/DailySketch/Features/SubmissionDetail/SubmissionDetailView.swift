import SwiftUI

struct SubmissionDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var model: SubmissionDetailViewModel
    @State private var showsDeleteConfirmation = false
    @State private var showsPlaceholderAction = false
    @State private var placeholderActionMessage = ""

    init(model: SubmissionDetailViewModel) {
        _model = State(initialValue: model)
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
                    title: "Sketch deleted",
                    message: "This submission is no longer available."
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
        .alert("Coming soon", isPresented: $showsPlaceholderAction) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(placeholderActionMessage)
        }
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var overflowMenu: some View {
        Menu {
            Button {
                presentPlaceholder("Native share arrives in a later phase.")
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            if model.isOwner {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete Submission", systemImage: "trash")
                }
                .disabled(model.isDeleting)
            } else {
                Button {
                    presentPlaceholder("Reporting arrives in Phase 11.")
                } label: {
                    Label("Report", systemImage: "exclamationmark.bubble")
                }
                Button {
                    presentPlaceholder("Blocking arrives in Phase 11.")
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
                action: {
                    presentPlaceholder("Likes arrive in Phase 9.")
                }
            )
            SocialActionButton(
                kind: .reflection,
                count: submission.reflectionCount,
                action: {
                    presentPlaceholder("Reflections arrive in Phase 9.")
                }
            )
            SocialActionButton(
                kind: .share,
                usesLabel: true,
                action: {
                    presentPlaceholder("Native share arrives in a later phase.")
                }
            )
            Spacer()
        }
    }

    private func artworkLabel(for submission: SubmissionModel) -> String {
        if let caption = submission.caption, !caption.isEmpty {
            return "Sketch by \(submission.displayName). \(caption)"
        }
        return "Sketch by \(submission.displayName). Prompt: \(submission.promptWords.joined(separator: ", "))"
    }

    private func presentPlaceholder(_ message: String) {
        placeholderActionMessage = message
        showsPlaceholderAction = true
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
                        username: "sketchy",
                        displayName: "Sketcher",
                        promptWords: ["Chocolate", "Coffee", "Banana"],
                        promptDate: Date(),
                        sketchSessionId: UUID(),
                        publishedAt: Date()
                    )
                    return repo
                }(),
                accessTokenProvider: { "token" }
            )
        )
    }
    .environment(AppDependencies.live)
    .preferredColorScheme(.dark)
}
