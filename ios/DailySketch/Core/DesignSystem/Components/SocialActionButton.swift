import SwiftUI

enum SocialActionKind {
    case like
    case reflection
    case share

    var systemImage: String {
        switch self {
        case .like: "heart"
        case .reflection: "bubble.left"
        case .share: "square.and.arrow.up"
        }
    }

    var activeSystemImage: String {
        switch self {
        case .like: "heart.fill"
        case .reflection: "bubble.left.fill"
        case .share: "square.and.arrow.up"
        }
    }

    var accessibilityNoun: String {
        switch self {
        case .like: "Like"
        case .reflection: "Reflections"
        case .share: "Share"
        }
    }
}

struct SocialActionButton: View {
    let kind: SocialActionKind
    var count: Int?
    var isActive: Bool = false
    var isDisabled: Bool = false
    var usesLabel: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: isActive ? kind.activeSystemImage : kind.systemImage)
                    .font(.body)
                    .scaleEffect(isActive && kind == .like && !reduceMotion ? 1.08 : 1.0)
                if let count {
                    Text("\(count)")
                        .font(AppTypography.caption)
                } else if usesLabel {
                    Text(kind.accessibilityNoun)
                        .font(AppTypography.caption)
                }
            }
            .foregroundStyle(isActive ? AppColors.primary : AppColors.textSecondary)
            .frame(minWidth: AppSpacing.minimumTouchTarget, minHeight: AppSpacing.minimumTouchTarget)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: isActive)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        switch kind {
        case .like:
            let selection = isActive ? "Unlike, selected" : "Like, not selected"
            if let count {
                return "\(selection), \(count)"
            }
            return selection
        case .reflection:
            if let count {
                return "\(kind.accessibilityNoun), \(count)"
            }
            return kind.accessibilityNoun
        case .share:
            return kind.accessibilityNoun
        }
    }
}

#Preview("Light") {
    HStack(spacing: AppSpacing.lg) {
        SocialActionButton(kind: .like, count: 24, isActive: false, action: {})
        SocialActionButton(kind: .like, count: 25, isActive: true, action: {})
        SocialActionButton(kind: .reflection, count: 3, action: {})
        SocialActionButton(kind: .share, usesLabel: true, action: {})
    }
    .padding()
    .background(AppColors.background)
}

#Preview("Dark") {
    HStack(spacing: AppSpacing.lg) {
        SocialActionButton(kind: .like, count: 0, action: {})
        SocialActionButton(kind: .reflection, count: 0, action: {})
        SocialActionButton(kind: .share, usesLabel: true, action: {})
    }
    .padding()
    .background(AppColors.background)
    .preferredColorScheme(.dark)
}
