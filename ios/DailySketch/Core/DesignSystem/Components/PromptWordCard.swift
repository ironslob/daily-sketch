import SwiftUI

struct PromptWordCard: View {
    enum Style {
        /// Full-width card in the 1+2 PromptGroup layout (Stitch bento hero).
        case hero
        /// Half-width card in the 1+2 PromptGroup layout.
        case compact
        /// Full-width card when stacking for accessibility sizes.
        case stacked
        /// Portrait playing-card used in the homepage fan stack.
        case stack
    }

    static let stackCardWidth: CGFloat = 200

    let word: String
    var style: Style = .hero

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Image(systemName: PromptWordSymbol.systemName(for: word))
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(AppColors.textPrimary.opacity(0.45))
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            Text(word)
                .font(wordFont)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(cardPadding)
        .frame(maxWidth: style == .stack ? nil : .infinity, alignment: .topLeading)
        .frame(width: style == .stack ? Self.stackCardWidth : nil)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(AppColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous))
        .accessibilityLabel(word)
    }

    private var wordFont: Font {
        switch style {
        case .hero, .stack:
            return AppTypography.title3
        case .compact, .stacked:
            return AppTypography.headline
        }
    }

    private var iconSize: CGFloat {
        switch style {
        case .hero, .stack: 28
        case .compact, .stacked: 24
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
        case .stack: 1 / 1.15
        }
    }
}

enum PromptWordSymbol {
    static func systemName(for word: String) -> String {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "chocolate", "cookie", "cake", "dessert", "candy":
            return "birthday.cake"
        case "coffee", "tea", "mug", "espresso":
            return "cup.and.saucer.fill"
        case "banana", "apple", "orange", "fruit", "lemon", "berry":
            return "leaf.fill"
        case "mirror", "glass", "window":
            return "circle.lefthalf.filled"
        case "cat", "dog", "bird", "fish":
            return "pawprint.fill"
        case "tree", "forest", "plant", "flower":
            return "tree.fill"
        case "sun", "moon", "star", "cloud", "rain":
            return "sparkles"
        case "book", "page", "letter":
            return "book.closed.fill"
        case "music", "song", "note":
            return "music.note"
        case "house", "home", "door":
            return "house.fill"
        default:
            return "sparkles"
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
    PromptWordCard(word: "Coffee", style: .stack)
        .padding()
        .background(AppColors.background)
}

#Preview("Dark") {
    PromptWordCard(word: "Chocolate", style: .hero)
        .padding()
        .background(AppColors.background)
        .preferredColorScheme(.dark)
}
