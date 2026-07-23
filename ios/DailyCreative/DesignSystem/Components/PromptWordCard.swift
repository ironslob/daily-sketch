import SwiftUI

struct PromptWordCard: View {
    enum Style {
        /// Full-width card in the 1+2 PromptGroup layout (Stitch bento hero).
        case hero
        /// Half-width card in the 1+2 PromptGroup layout.
        case compact
        /// Full-width card when stacking for accessibility sizes.
        case stacked
        /// Square playing-card used in the homepage prompt stack.
        case stack
    }

    static let stackCardWidth: CGFloat = 140

    let word: String
    var style: Style = .hero
    /// Horizontal alignment for the word inside the card.
    var contentAlignment: HorizontalAlignment = .leading

    var body: some View {
        let content = Text(word)
            .font(wordFont)
            .foregroundStyle(AppColors.textPrimary)
            .multilineTextAlignment(textAlignment)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
            .padding(cardPadding)

        Group {
            if style == .stack {
                content
                    .frame(width: Self.stackCardWidth, height: Self.stackCardWidth)
            } else {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .aspectRatio(aspectRatio, contentMode: .fit)
            }
        }
        .background(AppColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous))
        .accessibilityLabel(word)
    }

    private var textAlignment: TextAlignment {
        switch contentAlignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private var frameAlignment: Alignment {
        switch contentAlignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private var wordFont: Font {
        switch style {
        case .hero, .stack:
            return AppTypography.title3
        case .compact, .stacked:
            return AppTypography.headline
        }
    }

    private var cardPadding: CGFloat {
        switch style {
        case .hero: AppSpacing.cardPadding + 4
        case .stack: AppSpacing.cardPadding + 4
        case .compact, .stacked: AppSpacing.cardPadding
        }
    }

    private var aspectRatio: CGFloat {
        switch style {
        case .hero: 2
        case .compact: 1
        case .stacked: 2.4
        case .stack: 1
        }
    }
}

#Preview("Hero") {
    PromptWordCard(word: "Chocolate", style: .hero)
        .padding()
        .background(AppColors.background)
        .preferredColorScheme(.light)
}

#Preview("Compact") {
    HStack(spacing: AppSpacing.contentGap) {
        PromptWordCard(word: "Coffee", style: .compact)
        PromptWordCard(word: "Banana", style: .compact)
    }
    .padding()
    .background(AppColors.background)
}

#Preview("Stack") {
    PromptWordCard(word: "Coffee", style: .stack, contentAlignment: .center)
        .padding()
        .background(AppColors.background)
}

#Preview("Dark") {
    PromptWordCard(word: "Chocolate", style: .hero)
        .padding()
        .background(AppColors.background)
        .preferredColorScheme(.dark)
}
