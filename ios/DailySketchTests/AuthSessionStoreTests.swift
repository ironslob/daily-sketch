import XCTest
@testable import DailySketch

@MainActor
final class AuthSessionStoreTests: XCTestCase {
    func testGuestShellStartsUnauthenticated() async {
        let store = makeStore()
        XCTAssertFalse(store.isAuthenticated)
        if case .guest = store.state {
            // expected
        } else {
            XCTFail("Expected guest state")
        }
    }

    func testSignInChangesAppStateAndAttachesToken() async {
        let meFetcher = RecordingMeFetcher(
            profile: CurrentUserProfile(
                id: UUID(),
                username: nil,
                displayName: "Ada",
                profileCompleted: false,
                status: "incomplete"
            )
        )
        let authService = MockAuthService()
        let store = AuthSessionStore(authService: authService, meFetcher: meFetcher)

        await store.signIn(displayName: "Ada")

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.currentUser?.displayName, "Ada")
        XCTAssertNotNil(meFetcher.lastAccessToken)
        XCTAssertEqual(DailySketchAPITokenBridge.currentToken, meFetcher.lastAccessToken)
        XCTAssertTrue(meFetcher.lastAccessToken?.split(separator: ".").count == 3)
    }

    func testSignOutReturnsToGuestAndClearsToken() async {
        let meFetcher = RecordingMeFetcher(
            profile: CurrentUserProfile(
                id: UUID(),
                username: nil,
                displayName: "Ada",
                profileCompleted: false,
                status: "incomplete"
            )
        )
        let store = AuthSessionStore(authService: MockAuthService(), meFetcher: meFetcher)
        await store.signIn(displayName: "Ada")
        XCTAssertTrue(store.isAuthenticated)

        await store.signOut()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.currentUser)
        XCTAssertNil(DailySketchAPITokenBridge.currentToken)
        if case .guest = store.state {
            // expected
        } else {
            XCTFail("Expected guest after sign-out")
        }
    }

    func testExpiredSessionHandledGracefully() async {
        let meFetcher = RecordingMeFetcher(
            profile: CurrentUserProfile(
                id: UUID(),
                username: nil,
                displayName: "Ada",
                profileCompleted: false,
                status: "incomplete"
            )
        )
        meFetcher.error = AuthServiceError.sessionExpired
        let store = AuthSessionStore(authService: MockAuthService(), meFetcher: meFetcher)

        await store.signIn(displayName: "Ada")

        XCTAssertFalse(store.isAuthenticated)
        if case .failed(let message) = store.state {
            XCTAssertTrue(message.lowercased().contains("session"))
        } else {
            XCTFail("Expected failed state for expired session")
        }
    }

    func testBootstrapRestoresPersistedMockSession() async {
        let authService = MockAuthService()
        let meFetcher = RecordingMeFetcher(
            profile: CurrentUserProfile(
                id: UUID(),
                username: nil,
                displayName: "Persisted",
                profileCompleted: false,
                status: "incomplete"
            )
        )
        let first = AuthSessionStore(authService: authService, meFetcher: meFetcher)
        await first.signUp(displayName: "Persisted")
        XCTAssertTrue(first.isAuthenticated)

        let second = AuthSessionStore(authService: authService, meFetcher: meFetcher)
        await second.bootstrap()
        XCTAssertTrue(second.isAuthenticated)
        XCTAssertEqual(second.currentUser?.displayName, "Persisted")
    }

    private func makeStore() -> AuthSessionStore {
        AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: RecordingMeFetcher(
                profile: CurrentUserProfile(
                    id: UUID(),
                    username: nil,
                    displayName: "Test",
                    profileCompleted: false,
                    status: "incomplete"
                )
            )
        )
    }
}
