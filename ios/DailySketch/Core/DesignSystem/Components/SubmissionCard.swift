import SwiftUI

struct SubmissionCard: View {
    let item: FeedItemModel
    var onTapArtwork: () -> Void
    var onTapOwner: () -> Void
    var onTapLike: (() -> Void)?
    var onTapReflection: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ownerRow
            artwork
            metadataRow
            if let caption = item.captionPreview, !caption.isEmpty {
                Text(caption)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
                    .accessibilityLabel("Caption preview: \(caption)")
            }
            socialRow
        }
        .accessibilityElement(children: .contain)
    }

    private var ownerRow: some View {
        Button(action: onTapOwner) {
            HStack(spacing: AppSpacing.xs) {
                AvatarView(
                    displayName: item.displayName,
                    username: item.username,
                    avatarURL: item.avatarURL,
                    size: .feed
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("@\(item.username)")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: AppSpacing.xs)
                Text(item.relativePublishedAt)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.displayName), @\(item.username)")
        .accessibilityHint("Opens profile")
    }

    private var artwork: some View {
        Button(action: onTapArtwork) {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .empty:
                    LoadingSkeleton(height: 280)
                        .accessibilityLabel("Loading artwork")
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 480)
                case .failure:
                    RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
                        .fill(AppColors.surfaceTertiary)
                        .frame(height: 220)
                        .overlay {
                            Text("Couldn’t load image")
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(artworkAccessibilityLabel)
        .accessibilityHint("Opens sketch detail")
    }

    private var metadataRow: some View {
        Text(item.metadataLine)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textTertiary)
            .accessibilityLabel(item.metadataLine)
    }

    private var socialRow: some View {
        HStack(spacing: AppSpacing.lg) {
            SocialActionButton(
                kind: .like,
                count: item.likeCount,
                isActive: item.viewerHasLiked,
                action: { onTapLike?() }
            )
            SocialActionButton(
                kind: .reflection,
                count: item.reflectionCount,
                action: { onTapReflection?() }
            )
            Spacer()
        }
    }

    private var artworkAccessibilityLabel: String {
        if let caption = item.captionPreview, !caption.isEmpty {
            return "Sketch by \(item.displayName). \(caption)"
        }
        return "Sketch by \(item.displayName). Prompt: \(item.promptWords.joined(separator: ", "))"
    }
}

#Preview("Light") {
    ScrollView {
        SubmissionCard(
            item: FeedItemModel.preview,
            onTapArtwork: {},
            onTapOwner: {}
        )
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }
    .background(AppColors.background)
}

#Preview("Dark") {
    ScrollView {
        SubmissionCard(
            item: FeedItemModel.preview,
            onTapArtwork: {},
            onTapOwner: {}
        )
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }
    .background(AppColors.background)
    .preferredColorScheme(.dark)
}
