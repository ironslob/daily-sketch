import Foundation
import Observation

@Observable
final class AppDependencies {
    let environment: AppEnvironment
    let navigation: AppNavigationStore
    let auth: AuthSessionStore
    let descopeAuthService: DescopeAuthService?

    init(
        environment: AppEnvironment,
        navigation: AppNavigationStore = AppNavigationStore(),
        auth: AuthSessionStore,
        descopeAuthService: DescopeAuthService? = nil
    ) {
        self.environment = environment
        self.navigation = navigation
        self.auth = auth
        self.descopeAuthService = descopeAuthService
    }

    @MainActor
    static var live: AppDependencies {
        let environment = AppEnvironment.current
        let meFetcher = MeRepository(baseURL: environment.apiBaseURL)
        let projectID = environment.descopeProjectID

        if projectID == DescopeConfig.placeholderProjectID || projectID.isEmpty {
            let authService = MockAuthService()
            let auth = AuthSessionStore(authService: authService, meFetcher: meFetcher)
            return AppDependencies(environment: environment, auth: auth, descopeAuthService: nil)
        }

        let descope = DescopeAuthService(projectID: projectID)
        let auth = AuthSessionStore(authService: descope, meFetcher: meFetcher)
        return AppDependencies(environment: environment, auth: auth, descopeAuthService: descope)
    }
}
