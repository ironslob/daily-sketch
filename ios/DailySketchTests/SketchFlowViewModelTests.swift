import XCTest
@testable import DailySketch

@MainActor
final class SketchFlowViewModelTests: XCTestCase {
    private let prompt = DailyPromptModel(
        id: UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-ef1234567890")!,
        promptDate: Date(timeIntervalSince1970: 1_784_332_800),
        word1: "Chocolate",
        word2: "Coffee",
        word3: "Banana",
        status: "published",
        publishedAt: Date(timeIntervalSince1970: 1_784_246_400)
    )

    private func makeFlow(
        guestStore: InMemoryGuestTimerPreferenceStore = InMemoryGuestTimerPreferenceStore(),
        activeStore: InMemoryActiveSessionStore = InMemoryActiveSessionStore()
    ) -> SketchFlowViewModel {
        let profile = CurrentUserProfile(
            id: UUID(),
            username: nil,
            displayName: "Guest",
            profileCompleted: false,
            status: "incomplete"
        )
        let auth = AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: RecordingMeFetcher(profile: profile)
        )
        return SketchFlowViewModel(
            auth: auth,
            preferencesService: RecordingMeFetcher(profile: profile),
            guestTimerStore: guestStore,
            activeSessionStore: activeStore,
            sessionService: RecordingSketchSessionRepository()
        )
    }

    func testSheetAppearsByDefault() async {
        let flow = makeFlow()
        flow.startSketch(prompt: prompt)

        let deadline = Date().addingTimeInterval(1)
        while !flow.showsTimerSelection, Date() < deadline {
            await Task.yield()
        }

        XCTAssertTrue(flow.showsTimerSelection)
        XCTAssertFalse(flow.showsActiveSession)
    }

    func testRememberedTimerBypassesSheet() async {
        let guestStore = InMemoryGuestTimerPreferenceStore()
        guestStore.save(.threeMinutes)
        let flow = makeFlow(guestStore: guestStore)

        flow.startSketch(prompt: prompt)

        let deadline = Date().addingTimeInterval(1)
        while !flow.showsActiveSession, Date() < deadline {
            await Task.yield()
        }

        XCTAssertFalse(flow.showsTimerSelection)
        XCTAssertTrue(flow.showsActiveSession)
        XCTAssertEqual(flow.sessionViewModel?.timerOption, .threeMinutes)
        XCTAssertTrue(flow.changeTimerHintVisible)
    }

    func testNoTimerCanBeRemembered() async {
        let guestStore = InMemoryGuestTimerPreferenceStore()
        let flow = makeFlow(guestStore: guestStore)
        flow.selectedTimerOption = .noTimer
        flow.rememberChoice = true
        flow.confirmTimerSelection(prompt: prompt)

        let deadline = Date().addingTimeInterval(1)
        while !flow.showsActiveSession, Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(guestStore.load(), .noTimer)
        XCTAssertEqual(flow.sessionViewModel?.timerOption, .noTimer)
    }
}
