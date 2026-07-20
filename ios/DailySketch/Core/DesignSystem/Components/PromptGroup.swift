import SwiftUI

struct PromptGroup: View {
    let words: [String]
    var accessibilityLabel: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                gridLayout
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var gridLayout: some View {
        VStack(alignment: .leading, spacing: AppSpacing.contentGap) {
            if let first = words.first {
                PromptWordCard(word: first, style: .hero)
            }
            if words.count > 1 {
                HStack(spacing: AppSpacing.contentGap) {
                    ForEach(Array(words.dropFirst().enumerated()), id: \.offset) { _, word in
                        PromptWordCard(word: word, style: .compact)
                    }
                }
            }
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: AppSpacing.contentGap) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                PromptWordCard(word: word, style: .stacked)
            }
        }
    }
}

#Preview("Three words") {
    PromptGroup(
        words: ["Chocolate", "Coffee", "Banana"],
        accessibilityLabel: "Today’s prompt: Chocolate, Coffee, Banana."
    )
    .padding()
    .background(AppColors.background)
}

#Preview("Accessibility stack") {
    PromptGroup(
        words: ["Chocolate", "Coffee", "Banana"],
        accessibilityLabel: "Today’s prompt: Chocolate, Coffee, Banana."
    )
    .environment(\.dynamicTypeSize, .accessibility3)
    .padding()
    .background(AppColors.background)
}
