import SwiftUI

struct PromptWordCard: View {
    let word: String

    var body: some View {
        Text(word)
            .font(AppTypography.title3)
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(AppSpacing.cardPadding)
            .background(AppColors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous))
            .accessibilityLabel(word)
    }
}

#Preview("Light") {
    PromptWordCard(word: "Chocolate")
        .padding()
        .background(AppColors.background)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    PromptWordCard(word: "Chocolate")
        .padding()
        .background(AppColors.background)
        .preferredColorScheme(.dark)
}
