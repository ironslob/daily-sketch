import SwiftUI

struct SketchSessionView: View {
    @Bindable var model: SketchSessionViewModel

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: AppSpacing.contentGapLarge) {
                Spacer(minLength: AppSpacing.lg)

                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityHidden(true)

                Text("SKETCHING…")
                    .font(AppTypography.labelCaps)
                    .foregroundStyle(AppColors.textSecondary)
                    .tracking(1.2)

                if model.isCountdown {
                    Text(model.formattedCountdown)
                        .font(AppTypography.timer)
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()
                        .accessibilityLabel("Time remaining \(model.formattedCountdown)")
                } else {
                    VStack(spacing: AppSpacing.sm) {
                        Text("Sketching…")
                            .font(AppTypography.title2)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(model.formattedElapsed)
                            .font(AppTypography.title3.monospacedDigit())
                            .foregroundStyle(AppColors.textTertiary)
                            .accessibilityLabel("Elapsed \(model.formattedElapsed)")
                    }
                }

                DisclosureGroup {
                    PromptGroup(
                        words: model.promptWords,
                        accessibilityLabel: model.promptAccessibilityLabel
                    )
                    .padding(.top, AppSpacing.sm)
                } label: {
                    Text("Today’s prompt")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .tint(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.screenHorizontal)

                if model.syncPending, let message = model.syncErrorMessage {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                }

                Spacer()

                controls
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.bottom, AppSpacing.lg)
            }
        }
        .alert(
            "End this sketch session?",
            isPresented: Binding(
                get: { model.showsCancelConfirmation },
                set: { if !$0 { model.dismissCancelConfirmation() } }
            )
        ) {
            Button("Keep Sketching", role: .cancel) {
                model.dismissCancelConfirmation()
            }
            Button("End Session", role: .destructive) {
                model.confirmCancel()
            }
        } message: {
            Text("Your progress for this session will be discarded.")
        }
        .alert(
            "Photo capture is coming soon",
            isPresented: Binding(
                get: { model.showsPhotoPlaceholder },
                set: { if !$0 { model.dismissPhotoPlaceholder() } }
            )
        ) {
            Button("OK") {
                model.dismissPhotoPlaceholder()
            }
        } message: {
            Text("Your session is ready for a photo in the next update. You can resume it from Home until then.")
        }
        .onAppear {
            model.startTicking()
        }
        .onDisappear {
            model.stopTicking()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .timerCompleted:
            VStack(spacing: AppSpacing.contentGap) {
                PrimaryButton(
                    title: "Take Photo",
                    action: { model.takePhotoPlaceholder() },
                    systemImage: "camera"
                )
                SecondaryButton(
                    title: "Keep Sketching",
                    action: { model.keepSketchingAfterTimer() }
                )
                SecondaryButton(
                    title: "Cancel",
                    action: { model.requestCancel() },
                    systemImage: "xmark"
                )
            }

        case .readyForPhoto:
            VStack(spacing: AppSpacing.contentGap) {
                PrimaryButton(
                    title: "Take Photo",
                    action: { model.takePhotoPlaceholder() },
                    systemImage: "camera"
                )
                SecondaryButton(
                    title: "Cancel",
                    action: { model.requestCancel() },
                    systemImage: "xmark"
                )
            }

        case .paused:
            VStack(spacing: AppSpacing.contentGap) {
                PrimaryButton(
                    title: "Resume",
                    action: { model.resume() },
                    systemImage: "play.fill"
                )
                HStack(spacing: AppSpacing.contentGap) {
                    SecondaryButton(
                        title: "Finish",
                        action: { model.finish() },
                        systemImage: "checkmark"
                    )
                    SecondaryButton(
                        title: "Cancel",
                        action: { model.requestCancel() },
                        systemImage: "xmark"
                    )
                }
            }

        case .running:
            VStack(spacing: AppSpacing.contentGap) {
                if model.isCountdown {
                    PrimaryButton(
                        title: "Pause",
                        action: { model.pause() },
                        systemImage: "pause.fill"
                    )
                } else {
                    PrimaryButton(
                        title: "Finish",
                        action: { model.finish() },
                        systemImage: "checkmark"
                    )
                }
                HStack(spacing: AppSpacing.contentGap) {
                    if model.isCountdown {
                        SecondaryButton(
                            title: "Finish",
                            action: { model.finish() },
                            systemImage: "checkmark"
                        )
                    }
                    SecondaryButton(
                        title: "Cancel",
                        action: { model.requestCancel() },
                        systemImage: "xmark"
                    )
                }
            }

        case .abandoned:
            EmptyView()
        }
    }
}

#Preview("Countdown") {
    SketchSessionView(
        model: SketchSessionViewModel(
            prompt: DailyPromptModel(
                id: UUID(),
                promptDate: Date(),
                word1: "Chocolate",
                word2: "Coffee",
                word3: "Banana",
                status: "published",
                publishedAt: Date()
            ),
            timerOption: .fiveMinutes,
            isGuest: true,
            accessTokenProvider: { nil },
            sessionService: RecordingSketchSessionRepository(),
            activeSessionStore: InMemoryActiveSessionStore(),
            onEnded: {}
        )
    )
}

#Preview("No Timer Dark") {
    SketchSessionView(
        model: SketchSessionViewModel(
            prompt: DailyPromptModel(
                id: UUID(),
                promptDate: Date(),
                word1: "Chocolate",
                word2: "Coffee",
                word3: "Banana",
                status: "published",
                publishedAt: Date()
            ),
            timerOption: .noTimer,
            isGuest: true,
            accessTokenProvider: { nil },
            sessionService: RecordingSketchSessionRepository(),
            activeSessionStore: InMemoryActiveSessionStore(),
            onEnded: {}
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("Loading Sync") {
    SketchSessionView(
        model: {
            let model = SketchSessionViewModel(
                prompt: DailyPromptModel(
                    id: UUID(),
                    promptDate: Date(),
                    word1: "Chocolate",
                    word2: "Coffee",
                    word3: "Banana",
                    status: "published",
                    publishedAt: Date()
                ),
                timerOption: .oneMinute,
                syncPending: true,
                isGuest: false,
                accessTokenProvider: { nil },
                sessionService: RecordingSketchSessionRepository(),
                activeSessionStore: InMemoryActiveSessionStore(),
                onEnded: {}
            )
            model.markSyncPending("Couldn’t reach the server. Keep sketching.")
            return model
        }()
    )
}
