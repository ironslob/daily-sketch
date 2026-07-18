import Foundation
import Observation

@Observable
final class AppDependencies {
    let environment: AppEnvironment
    let navigation: AppNavigationStore
    let auth: AuthSessionStore
    let descopeAuthService: DescopeAuthService?
    let preferencesService: any PreferencesServing
    let profileUpdater: any ProfileUpdating
    let promptRepository: PromptRepository

    init(
        environment: AppEnvironment,
        navigation: AppNavigationStore = AppNavigationStore(),
        auth: AuthSessionStore,
        descopeAuthService: DescopeAuthService? = nil,
        preferencesService: any PreferencesServing,
        profileUpdater: any ProfileUpdating,
        promptRepository: PromptRepository
    ) {
        self.environment = environment
        self.navigation = navigation
        self.auth = auth
        self.descopeAuthService = descopeAuthService
        self.preferencesService = preferencesService
        self.profileUpdater = profileUpdater
        self.promptRepository = promptRepository
    }

    @MainActor
    static var live: AppDependencies {
        let environment = AppEnvironment.current
        let repository = MeRepository(baseURL: environment.apiBaseURL)
        let promptRepository = PromptRepository(baseURL: environment.apiBaseURL)
        let projectID = environment.descopeProjectID

        if projectID == DescopeConfig.placeholderProjectID || projectID.isEmpty {
            let authService = MockAuthService()
            let auth = AuthSessionStore(
                authService: authService,
                meFetcher: repository,
                profileUpdater: repository
            )
            return AppDependencies(
                environment: environment,
                auth: auth,
                descopeAuthService: nil,
                preferencesService: repository,
                profileUpdater: repository,
                promptRepository: promptRepository
            )
        }

        let descope = DescopeAuthService(projectID: projectID)
        let auth = AuthSessionStore(
            authService: descope,
            meFetcher: repository,
            profileUpdater: repository
        )
        return AppDependencies(
            environment: environment,
            auth: auth,
            descopeAuthService: descope,
            preferencesService: repository,
            profileUpdater: repository,
            promptRepository: promptRepository
        )
    }
}
