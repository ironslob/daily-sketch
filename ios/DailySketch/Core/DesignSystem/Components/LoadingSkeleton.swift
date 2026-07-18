import SwiftUI

struct LoadingSkeleton: View {
    var height: CGFloat = 120

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
            .fill(AppColors.surfaceSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
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
