import SwiftUI

struct TimerSelectionView: View {
    @Binding var selectedOption: TimerPreferenceOption?
    @Binding var rememberChoice: Bool
    let onStart: () -> Void
    let onDismiss: () -> Void
    var isStarting: Bool = false

    @State private var selectedDetent: PresentationDetent = .fraction(0.72)

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColors.outline)
                .frame(width: 48, height: 5)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)

            Text("How long would you like to sketch?")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.bottom, AppSpacing.md)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(TimerPreferenceOption.allCases) { option in
                        timerRow(option)
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.bottom, AppSpacing.md)
            }

            footer
        }
        .background(AppColors.background)
        .presentationDetents([.fraction(0.72), .large], selection: $selectedDetent)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isStarting)
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.md) {
            Button {
                rememberChoice.toggle()
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: rememberChoice ? "checkmark.square.fill" : "square")
                        .font(.body)
                        .foregroundStyle(rememberChoice ? AppColors.primary : AppColors.outline)
                    Text("Remember this choice")
                        .font(AppTypography.bodySmall)
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
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.xl)
        .background(AppColors.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)
        }
    }

    private func timerRow(_ option: TimerPreferenceOption) -> some View {
        let isSelected = selectedOption == option

        return Button {
            selectedOption = option
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack {
                Text(option.rawValue)
                    .font(AppTypography.bodyLarge)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? AppColors.primary : AppColors.outline,
                            lineWidth: 2
                        )
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: AppSpacing.minimumTouchTarget)
            .contentShape(RoundedRectangle(cornerRadius: AppRadii.medium, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: AppRadii.medium, style: .continuous)
                    .fill(isSelected ? AppColors.surfaceSecondary : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
