import SwiftUI

struct LoadingSkeleton: View {
    var height: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase = false

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
            .fill(AppColors.surfaceSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .opacity(reduceMotion ? 1 : (shimmerPhase ? 0.92 : 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: shimmerPhase)
            .onAppear {
                guard !reduceMotion else { return }
                shimmerPhase = true
            }
            .accessibilityLabel("Loading")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    VStack(spacing: AppSpacing.contentGap) {
        LoadingSkeleton(height: 72)
        LoadingSkeleton(height: 160)
    }
    .padding()
    .background(AppColors.background)
}
