import Foundation
import Observation

enum AppRoute: Hashable {
    case settings
    case authentication(AuthenticationView.Mode)
    case profileCompletion
    case submissionDetail(UUID)
    case publicProfile(username: String)
    case editProfile
    case blockedUsers
    case deleteAccount
}

enum AppTab: Hashable {
    case home
    case profile
}

@Observable
final class AppNavigationStore {
    var selectedTab: AppTab = .home
    var homePath: [AppRoute] = []
    var profilePath: [AppRoute] = []
    /// Set when a Submission is deleted so Home can refresh the community feed.
    var feedNeedsRefresh = false

    func openHomeFromReminder() {
        selectedTab = .home
        homePath.removeAll()
    }
}
