import SwiftUI

struct ReflectionRow: View {
    let reflection: ReflectionModel
    var onDelete: (() -> Void)?
    var onReport: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            AvatarView(displayName: reflection.displayName, username: reflection.username, size: .feed)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    Text(reflection.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("@\(reflection.username)")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer(minLength: 0)
                    Text(RelativeTimestampFormatter.string(from: reflection.createdAt))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                Text(reflection.body)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if reflection.isAuthor || onReport != nil {
                Menu {
                    if reflection.isAuthor {
                        Button(role: .destructive, action: { onDelete?() }) {
                            Label("Delete Reflection", systemImage: "trash")
                        }
                    } else if let onReport {
                        Button(action: onReport) {
                            Label("Report", systemImage: "exclamationmark.bubble")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(
                            minWidth: AppSpacing.minimumTouchTarget,
                            minHeight: AppSpacing.minimumTouchTarget
                        )
                }
                .accessibilityLabel("Reflection actions")
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadii.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(reflection.displayName). \(reflection.body). \(RelativeTimestampFormatter.string(from: reflection.createdAt))"
        )
    }
}

#Preview("Light") {
    ReflectionRow(
        reflection: ReflectionModel(
            id: UUID(),
            submissionId: UUID(),
            userId: UUID(),
            username: "calm_sketcher",
            displayName: "Casey",
            avatarURL: nil,
            body: "Such a warm interpretation of today’s words.",
            createdAt: Date().addingTimeInterval(-3_600),
            isAuthor: true
        ),
        onDelete: {}
    )
    .padding()
    .background(AppColors.background)
}

#Preview("Dark") {
    ReflectionRow(
        reflection: ReflectionModel(
            id: UUID(),
            submissionId: UUID(),
            userId: UUID(),
            username: "calm_sketcher",
            displayName: "Casey",
            avatarURL: nil,
            body: "Such a warm interpretation of today’s words.",
            createdAt: Date().addingTimeInterval(-3_600),
            isAuthor: false
        ),
        onReport: {}
    )
    .padding()
    .background(AppColors.background)
    .preferredColorScheme(.dark)
}
