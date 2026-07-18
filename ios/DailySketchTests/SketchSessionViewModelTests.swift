import XCTest
@testable import DailySketch

@MainActor
final class SketchSessionViewModelTests: XCTestCase {
    private let prompt = DailyPromptModel(
        id: UUID(),
        promptDate: Date(),
        word1: "Chocolate",
        word2: "Coffee",
        word3: "Banana",
        status: "published",
        publishedAt: Date()
    )

    func testCountdownSurvivesBackgroundingViaDateProvider() {
        let clock = ControllableDateProvider()
        let model = SketchSessionViewModel(
            prompt: prompt,
            timerOption: .oneMinute,
            startedAt: clock.now(),
            isGuest: true,
            accessTokenProvider: { nil },
            sessionService: RecordingSketchSessionRepository(),
            activeSessionStore: InMemoryActiveSessionStore(),
            dateProvider: clock,
            onEnded: {}
        )

        XCTAssertEqual(model.displayedCountdownSeconds, 60)

        // Simulate backgrounding for 20 seconds without local ticks.
        clock.advance(by: 20)
        model.pause()

        XCTAssertEqual(model.displayedCountdownSeconds, 40)
        XCTAssertEqual(model.phase, .paused)
        model.stopTicking()
    }

    func testPauseAndResumeAccumulateCorrectly() {
        let clock = ControllableDateProvider()
        let model = SketchSessionViewModel(
            prompt: prompt,
            timerOption: .oneMinute,
            startedAt: clock.now(),
            isGuest: true,
            accessTokenProvider: { nil },
            sessionService: RecordingSketchSessionRepository(),
            activeSessionStore: InMemoryActiveSessionStore(),
            dateProvider: clock,
            onEnded: {}
        )

        clock.advance(by: 10)
        model.pause()
        clock.advance(by: 30) // paused time must not consume countdown
        model.resume()
        clock.advance(by: 5)
        model.pause()

        XCTAssertEqual(model.displayedCountdownSeconds, 45)
        XCTAssertEqual(model.phase, .paused)
    }

    func testCancelConfirmationEndsSession() async {
        let store = InMemoryActiveSessionStore()
        var ended = false
        let model = SketchSessionViewModel(
            prompt: prompt,
            timerOption: .fiveMinutes,
            isGuest: true,
            accessTokenProvider: { nil },
            sessionService: RecordingSketchSessionRepository(),
            activeSessionStore: store,
            onEnded: { ended = true }
        )

        model.requestCancel()
        XCTAssertTrue(model.showsCancelConfirmation)
        model.confirmCancel()

        let deadline = Date().addingTimeInterval(1)
        while !ended, Date() < deadline {
            await Task.yield()
        }

        XCTAssertTrue(ended)
        XCTAssertEqual(model.phase, .abandoned)
        XCTAssertNil(try? store.load())
    }
}
