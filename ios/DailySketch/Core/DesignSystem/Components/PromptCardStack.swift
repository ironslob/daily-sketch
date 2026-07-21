import SwiftUI

enum PromptCardFanPhase: Equatable {
    case stacked
    case fannedOut
    case resting
}

struct PromptCardFanTransform: Equatable {
    let rotation: Double
    let xOffset: CGFloat
    let zIndex: Double
}

enum PromptCardFanGeometry {
    static let stackHeight: CGFloat = 220
    static let fanOutSpring = Animation.spring(response: 0.45, dampingFraction: 0.78)
    static let settleSpring = Animation.spring(response: 0.55, dampingFraction: 0.82)
    static let holdDuration: Duration = .milliseconds(150)

    static func transform(index: Int, phase: PromptCardFanPhase) -> PromptCardFanTransform {
        switch phase {
        case .stacked:
            PromptCardFanTransform(rotation: 0, xOffset: 0, zIndex: zIndex(for: index))
        case .resting:
            restingTransform(for: index)
        case .fannedOut:
            fannedOutTransform(for: index)
        }
    }

    private static func zIndex(for index: Int) -> Double {
        switch index {
        case 0: 1
        case 1: 3
        case 2: 2
        default: 0
        }
    }

    private static func restingTransform(for index: Int) -> PromptCardFanTransform {
        switch index {
        case 0:
            PromptCardFanTransform(rotation: -14, xOffset: -28, zIndex: 1)
        case 1:
            PromptCardFanTransform(rotation: 0, xOffset: 0, zIndex: 3)
        case 2:
            PromptCardFanTransform(rotation: 14, xOffset: 28, zIndex: 2)
        default:
            PromptCardFanTransform(rotation: 0, xOffset: 0, zIndex: 0)
        }
    }

    private static func fannedOutTransform(for index: Int) -> PromptCardFanTransform {
        switch index {
        case 0:
            PromptCardFanTransform(rotation: -28, xOffset: -56, zIndex: 1)
        case 1:
            PromptCardFanTransform(rotation: 0, xOffset: 0, zIndex: 3)
        case 2:
            PromptCardFanTransform(rotation: 28, xOffset: 56, zIndex: 2)
        default:
            PromptCardFanTransform(rotation: 0, xOffset: 0, zIndex: 0)
        }
    }
}

struct PromptCardStack: View {
    let words: [String]
    var accessibilityLabel: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var fanPhase: PromptCardFanPhase = .stacked
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                fanStackLayout
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            startIntroAnimationIfNeeded()
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: AppSpacing.contentGap) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                PromptWordCard(word: word, style: .stacked)
            }
        }
    }

    private var fanStackLayout: some View {
        ZStack {
            ForEach(Array(displayWords.enumerated()), id: \.offset) { index, word in
                let transform = PromptCardFanGeometry.transform(index: index, phase: fanPhase)

                PromptWordCard(word: word, style: .stack)
                    .rotationEffect(.degrees(transform.rotation), anchor: .bottom)
                    .offset(x: transform.xOffset)
                    .zIndex(transform.zIndex)
                    .appSoftShadow()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PromptCardFanGeometry.stackHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            replayFanAnimation()
        }
        .accessibilityHint("Double tap to replay the card fan animation")
    }

    private var displayWords: [String] {
        Array(words.prefix(3))
    }

    private func startIntroAnimationIfNeeded() {
        guard !dynamicTypeSize.isAccessibilitySize else { return }

        if reduceMotion {
            fanPhase = .resting
            return
        }

        fanPhase = .stacked
        runFanSequence(includeIntro: true)
    }

    private func replayFanAnimation() {
        guard !dynamicTypeSize.isAccessibilitySize, !reduceMotion else { return }
        guard fanPhase == .resting else { return }

        runFanSequence(includeIntro: false)
    }

    private func runFanSequence(includeIntro: Bool) {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            if includeIntro {
                fanPhase = .stacked
            }

            withAnimation(PromptCardFanGeometry.fanOutSpring) {
                fanPhase = .fannedOut
            }

            try? await Task.sleep(for: PromptCardFanGeometry.holdDuration)
            guard !Task.isCancelled else { return }

            withAnimation(PromptCardFanGeometry.settleSpring) {
                fanPhase = .resting
            }
        }
    }
}

#Preview("Resting fan") {
    PromptCardStackPreview(phase: .resting)
}

#Preview("Fanned out") {
    PromptCardStackPreview(phase: .fannedOut)
}

#Preview("Stacked") {
    PromptCardStackPreview(phase: .stacked)
}

private struct PromptCardStackPreview: View {
    let phase: PromptCardFanPhase

    var body: some View {
        ZStack {
            ForEach(Array(["Chocolate", "Coffee", "Banana"].enumerated()), id: \.offset) { index, word in
                let transform = PromptCardFanGeometry.transform(index: index, phase: phase)

                PromptWordCard(word: word, style: .stack)
                    .rotationEffect(.degrees(transform.rotation), anchor: .bottom)
                    .offset(x: transform.xOffset)
                    .zIndex(transform.zIndex)
                    .appSoftShadow()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PromptCardFanGeometry.stackHeight)
        .padding()
        .background(AppColors.background)
    }
}
