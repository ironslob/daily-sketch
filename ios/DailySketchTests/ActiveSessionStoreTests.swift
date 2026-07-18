import XCTest
@testable import DailySketch

final class ActiveSessionStoreTests: XCTestCase {
    func testGuestSessionPersistsLocally() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-session-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ActiveSessionStore(fileURL: url)
        let snapshot = ActiveSessionSnapshot(
            id: UUID(),
            serverSessionId: nil,
            promptId: UUID(),
            promptWords: ["Chocolate", "Coffee", "Banana"],
            promptAccessibilityLabel: "Today’s prompt: Chocolate, Coffee, Banana.",
            timerMode: "countdown",
            selectedTimerSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 1_784_376_000),
            pausedAt: nil,
            pausedTotalSeconds: 12,
            lifecycle: .paused,
            syncPending: false,
            isGuest: true
        )

        try store.save(snapshot)
        let loaded = try store.load()
        XCTAssertEqual(loaded, snapshot)

        try store.clear()
        XCTAssertNil(try store.load())
    }
}

final class GuestTimerPreferenceStoreTests: XCTestCase {
    func testPreferencePersistsInUserDefaults() {
        let suiteName = "guest-timer-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GuestTimerPreferenceStore(defaults: defaults)
        XCTAssertNil(store.load())

        store.save(.noTimer)
        XCTAssertEqual(store.load(), .noTimer)

        store.save(.tenMinutes)
        XCTAssertEqual(store.load(), .tenMinutes)

        store.clear()
        XCTAssertNil(store.load())
    }
}
