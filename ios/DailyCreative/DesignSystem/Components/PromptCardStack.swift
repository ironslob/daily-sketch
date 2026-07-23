import SwiftUI

enum PromptCardStackLayout {
    /// Approximate height used by homepage loading skeletons.
    static let height: CGFloat = 220
    /// How far the bottom row tucks under the top card.
    static let overlap: CGFloat = 28
}

struct PromptCardStack: View {
    let words: [String]
    var accessibilityLabel: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                overlappingLayout
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: AppSpacing.contentGap) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                PromptWordCard(word: word, style: .stacked)
            }
        }
    }

    private var overlappingLayout: some View {
        VStack(spacing: -PromptCardStackLayout.overlap) {
            if let first = displayWords.first {
                PromptWordCard(word: first, style: .hero, contentAlignment: .center)
                    .frame(maxWidth: .infinity)
                    .zIndex(2)
                    .appSoftShadow()
            }

            if displayWords.count > 1 {
                HStack(spacing: AppSpacing.contentGap) {
                    ForEach(Array(displayWords.dropFirst().enumerated()), id: \.offset) { _, word in
                        PromptWordCard(word: word, style: .compact)
                            .appSoftShadow()
                    }
                }
                .zIndex(1)
            }
        }
    }

    private var displayWords: [String] {
        Array(words.prefix(3))
    }
}

#Preview("Overlapping stack") {
    PromptCardStack(
        words: ["Chocolate", "Coffee", "Banana"],
        accessibilityLabel: "Today’s prompt: Chocolate, Coffee, Banana."
    )
    .padding()
    .background(AppColors.background)
}

#Preview("Accessibility stack") {
    PromptCardStack(
        words: ["Chocolate", "Coffee", "Banana"],
        accessibilityLabel: "Today’s prompt: Chocolate, Coffee, Banana."
    )
    .environment(\.dynamicTypeSize, .accessibility3)
    .padding()
    .background(AppColors.background)
}
