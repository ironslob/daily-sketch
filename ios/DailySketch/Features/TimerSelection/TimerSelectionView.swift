import SwiftUI

struct TimerSelectionView: View {
    @Binding var selectedOption: TimerPreferenceOption?
    @Binding var rememberChoice: Bool
    let onStart: () -> Void
    let onDismiss: () -> Void
    var isStarting: Bool = false

    var body: some View {
        VStack(spacing: AppSpacing.contentGapLarge) {
            Capsule()
                .fill(AppColors.outline)
                .frame(width: 40, height: 5)
                .padding(.top, AppSpacing.sm)

            Text("How long would you like to sketch?")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(TimerPreferenceOption.allCases) { option in
                    timerRow(option)
                    if option != TimerPreferenceOption.allCases.last {
                        Divider().overlay(AppColors.divider)
                    }
                }
            }

            Button {
                rememberChoice.toggle()
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: rememberChoice ? "checkmark.square.fill" : "square")
                        .foregroundStyle(rememberChoice ? AppColors.primary : AppColors.textSecondary)
                    Text("Remember this choice")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remember this choice")
            .accessibilityValue(rememberChoice ? "On" : "Off")

            PrimaryButton(
                title: isStarting ? "Starting…" : "Start",
                action: onStart,
                isDisabled: selectedOption == nil || isStarting,
                systemImage: "stopwatch"
            )
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.bottom, AppSpacing.lg)
        .background(AppColors.surfacePrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isStarting)
        .onDisappear {
            // Dismiss without Start must not create a session — handled by caller
            // only creating sessions from onStart.
        }
    }

    private func timerRow(_ option: TimerPreferenceOption) -> some View {
        Button {
            selectedOption = option
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack {
                Text(option.rawValue)
                    .font(AppTypography.bodyLarge)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Image(systemName: selectedOption == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedOption == option ? AppColors.primary : AppColors.outline)
            }
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.rawValue)
        .accessibilityAddTraits(selectedOption == option ? [.isSelected] : [])
    }
}

#Preview("Normal") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TimerSelectionView(
                selectedOption: .constant(.fiveMinutes),
                rememberChoice: .constant(false),
                onStart: {},
                onDismiss: {}
            )
        }
}

#Preview("Dark") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TimerSelectionView(
                selectedOption: .constant(nil),
                rememberChoice: .constant(false),
                onStart: {},
                onDismiss: {}
            )
        }
        .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TimerSelectionView(
                selectedOption: .constant(.noTimer),
                rememberChoice: .constant(true),
                onStart: {},
                onDismiss: {}
            )
        }
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
