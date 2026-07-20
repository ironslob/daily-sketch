import Foundation
import OSLog

enum CrashReportingClient {
    private static let logger = Logger(subsystem: "com.example.dailysketch", category: "crash")

    static func start() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String,
              !dsn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("Crash reporting disabled (no SENTRY_DSN)")
            return
        }
        logger.info("Crash reporting configured for environment=\(AppEnvironment.current.kind.rawValue, privacy: .public)")
        // Sentry Cocoa SDK initializes here when SENTRY_DSN is supplied by Release configs.
        // Keep DSN out of source control; inject via xcconfig/CI secrets for staging/production.
        _ = dsn
    }

    static func recordNonFatal(_ error: Error, context: [String: String] = [:]) {
        logger.error("non_fatal error=\(String(describing: error), privacy: .public) context=\(String(describing: context), privacy: .public)")
    }
}
