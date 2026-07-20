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

@Observable
final class AppNavigationStore {
    var homePath: [AppRoute] = []
    var profilePath: [AppRoute] = []
    /// Set when a Submission is deleted so Home can refresh the community feed.
    var feedNeedsRefresh = false
}
