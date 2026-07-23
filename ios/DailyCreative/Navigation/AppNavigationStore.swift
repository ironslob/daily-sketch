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
    /// Guest/auth publish paused for username completion; resume Review after save.
    var resumePublicationAfterProfileCompletion = false
    /// Home observes this to call retryPublish after profile completion.
    var publishResumeRequested = false

    func openHomeFromReminder() {
        selectedTab = .home
        homePath.removeAll()
    }

    func presentProfileCompletion(preferHome: Bool = false) {
        selectedTab = preferHome ? .home : .profile
        let path = preferHome ? homePath : profilePath
        if path.contains(.profileCompletion) { return }
        if preferHome {
            homePath.append(.profileCompletion)
        } else {
            profilePath.append(.profileCompletion)
        }
    }

    /// Clears auth routes after a successful sign-in/sign-up and routes incomplete
    /// profiles to profile completion. No-ops when auth did not succeed so the
    /// auth screen (and its error state) stays visible.
    func finishAuthenticationFlow(
        isAuthenticated: Bool,
        needsProfileCompletion: Bool
    ) {
        guard isAuthenticated else { return }
        profilePath.removeAll {
            $0 == .authentication(.signUp) || $0 == .authentication(.signIn)
        }
        homePath.removeAll {
            $0 == .authentication(.signUp) || $0 == .authentication(.signIn)
        }
        if needsProfileCompletion {
            presentProfileCompletion(preferHome: resumePublicationAfterProfileCompletion)
        }
    }

    func dismissProfileCompletion() {
        homePath.removeAll { $0 == .profileCompletion }
        profilePath.removeAll { $0 == .profileCompletion }
    }
}
