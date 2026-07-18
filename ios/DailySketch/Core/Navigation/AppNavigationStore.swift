import Foundation
import Observation

enum AppRoute: Hashable {
    case settings
    case authentication(AuthenticationView.Mode)
}

@Observable
final class AppNavigationStore {
    var homePath: [AppRoute] = []
    var profilePath: [AppRoute] = []
}
