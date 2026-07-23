import SwiftUI

struct StorySessionView: View {
    @Bindable var model: StorySessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: AppSpacing.section) {
            Spacer()

            VStack(spacing: AppSpacing.contentGap) {
                Text("Think about your story...")
                    .font(AppTypography.display)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                if let prompt = model.promptWords {
                    PromptCardStack(
                        words: prompt,
                        accessibilityLabel: "Prompt: \(prompt.joined(separator: ", "))"
                    )
                }
            }

            if model.showsTimer {
                Text(model.timerDisplay)
                    .font(.system(size: 64, weight: .light, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .monospacedDigit()
            }

            Spacer()

            VStack(spacing: AppSpacing.contentGap) {
                if model.showsTimer {
                    if model.isPaused {
                        PrimaryButton(title: "Resume", action: { model.resume() })
                    } else {
                        SecondaryButton(title: "Pause", action: { model.pause() })
                    }
                }

                PrimaryButton(
                    title: "Start Writing",
                    action: { model.finishEarly() }
                )

                TertiaryTextButton(title: "Abandon Session") {
                    model.abandon()
                    dismiss()
                }
            }
            .padding(.bottom, AppSpacing.section)
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .background(AppColors.background.ignoresSafeArea())
    }
}
