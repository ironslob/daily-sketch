import SwiftUI

struct PromptChip: View {
    let word: String

    var body: some View {
        Text(word.uppercased())
            .font(AppTypography.labelCaps)
            .tracking(0.8)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColors.surfaceTertiary)
            .clipShape(Capsule())
            .accessibilityLabel(word)
    }
}

#Preview("Light") {
    HStack(spacing: AppSpacing.xs) {
        PromptChip(word: "Chocolate")
        PromptChip(word: "Coffee")
        PromptChip(word: "Banana")
    }
    .padding()
    .background(AppColors.background)
}

#Preview("Dark") {
    HStack(spacing: AppSpacing.xs) {
        PromptChip(word: "Leaf")
        PromptChip(word: "Green")
        PromptChip(word: "Organic")
    }
    .padding()
    .background(AppColors.background)
    .preferredColorScheme(.dark)
}
