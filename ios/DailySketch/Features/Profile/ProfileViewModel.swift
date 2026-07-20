import Foundation
import Observation

enum ProfileContentState: Equatable {
    case loading
    case loaded
    case empty
    case failed(String)
}

@MainActor
@Observable
final class ProfileViewModel {
    enum Mode: Equatable {
        case own
        case other(username: String)
    }

    private(set) var profile: PublicProfileModel?
    private(set) var galleryItems: [FeedItemModel] = []
    private(set) var nextCursor: String?
    private(set) var isLoadingMore = false
    private(set) var contentState: ProfileContentState = .loading
    private(set) var isSelf = false

    let mode: Mode
    private let profileFetcher: any ProfileFetching
    private let accessTokenProvider: () -> String?
    private let ownUsernameProvider: () -> String?
    private let analytics: (any AnalyticsTracking)?
    private let pageSize = 20

    init(
        mode: Mode,
        profileFetcher: any ProfileFetching,
        accessTokenProvider: @escaping () -> String? = { nil },
        ownUsernameProvider: @escaping () -> String? = { nil },
        analytics: (any AnalyticsTracking)? = nil
    ) {
        self.mode = mode
        self.profileFetcher = profileFetcher
        self.accessTokenProvider = accessTokenProvider
        self.ownUsernameProvider = ownUsernameProvider
        self.analytics = analytics
    }

    var username: String? {
        switch mode {
        case .own:
            return ownUsernameProvider()
        case .other(let username):
            return username
        }
    }

    var showsOwnControls: Bool {
        switch mode {
        case .own:
            return true
        case .other:
            return isSelf
        }
    }

    var canLoadMore: Bool {
        nextCursor != nil && !isLoadingMore
    }

    var streakLabel: String {
        profile?.streakLabel ?? "0-day streak"
    }

    var submissionCountLabel: String {
        profile?.submissionCountLabel ?? "0 sketches"
    }

    func load() async {
        guard let username else {
            contentState = .failed("Complete your profile to view your sketch journal.")
            return
        }
        contentState = .loading
        do {
            let token = accessTokenProvider()
            let loaded = try await profileFetcher.fetchPublicProfile(
                username: username,
                accessToken: token
            )
            profile = loaded
            isSelf = loaded.isSelf || mode == .own
            let page = try await profileFetcher.fetchUserSubmissions(
                username: username,
                accessToken: token,
                cursor: nil,
                limit: pageSize
            )
            galleryItems = page.items
            nextCursor = page.nextCursor
            contentState = page.items.isEmpty ? .empty : .loaded
            analytics?.track(.profileViewed, properties: ["username": username])
        } catch {
            contentState = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        await load()
    }

    func loadMoreIfNeeded(currentItem: FeedItemModel) async {
        guard canLoadMore,
              let index = galleryItems.firstIndex(where: { $0.id == currentItem.id }),
              index >= galleryItems.count - 4,
              let username,
              let cursor = nextCursor
        else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await profileFetcher.fetchUserSubmissions(
                username: username,
                accessToken: accessTokenProvider(),
                cursor: cursor,
                limit: pageSize
            )
            let existingIDs = Set(galleryItems.map(\.id))
            let newItems = page.items.filter { !existingIDs.contains($0.id) }
            galleryItems.append(contentsOf: newItems)
            nextCursor = page.nextCursor
            if !galleryItems.isEmpty {
                contentState = .loaded
            }
        } catch {
            // Keep existing gallery on pagination failure.
        }
    }
}
