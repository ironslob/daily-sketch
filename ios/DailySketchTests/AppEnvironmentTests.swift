import XCTest
@testable import DailySketch

final class AppEnvironmentTests: XCTestCase {
    func testLocalEnvironmentDefaultsToLocalhost() {
        let environment = AppEnvironment(
            kind: .local,
            apiBaseURL: URL(string: "http://localhost:8000")!,
            descopeProjectID: "replace-me"
        )
        XCTAssertEqual(environment.kind, .local)
        XCTAssertEqual(environment.apiBaseURL.host, "localhost")
        XCTAssertEqual(environment.apiBaseURL.port, 8000)
        XCTAssertEqual(environment.descopeProjectID, "replace-me")
    }
}
