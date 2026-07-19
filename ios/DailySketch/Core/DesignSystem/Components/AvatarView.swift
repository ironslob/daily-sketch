import SwiftUI

struct AvatarView: View {
    enum Size {
        case feed
        case detail
        case profile

        var points: CGFloat {
            switch self {
            case .feed: 32
            case .detail: 48
            case .profile: 84
            }
        }
    }

    let displayName: String
    let username: String
    var avatarURL: URL?
    var size: Size = .feed

    var body: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size.points, height: size.points)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(AppColors.surfaceTertiary)
            if let initial = initials {
                Text(initial)
                    .font(size == .feed ? AppTypography.caption : AppTypography.bodySmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size.points * 0.4))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private var initials: String? {
        let source = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = source.isEmpty ? username : source
        guard let first = base.first else { return nil }
        return String(first).uppercased()
    }
}

#Preview("Light") {
    HStack(spacing: AppSpacing.md) {
        AvatarView(displayName: "Matt", username: "sketchy_matt", size: .feed)
        AvatarView(displayName: "Alex Rivers", username: "alexdraws", size: .detail)
        AvatarView(displayName: "", username: "", size: .profile)
    }
    .padding()
    .background(AppColors.background)
}

#Preview("Dark") {
    AvatarView(displayName: "Sam", username: "sam_creates", size: .detail)
        .padding()
        .background(AppColors.background)
        .preferredColorScheme(.dark)
}
