import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    var systemImage: String? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(AppTypography.headline)
            .foregroundStyle(AppColors.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.controlHeight)
            .background(AppColors.primary)
            .clipShape(Capsule())
            .appSoftShadow()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(title)
    }
}

#Preview {
    PrimaryButton(title: "Start Sketch") {}
        .padding()
        .background(AppColors.background)
}
