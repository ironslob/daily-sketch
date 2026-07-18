import Foundation

protocol DateProviding: Sendable {
    func now() -> Date
}

struct SystemDateProvider: DateProviding {
    func now() -> Date {
        Date()
    }
}

/// Mutable clock for deterministic timer tests.
final class ControllableDateProvider: DateProviding, @unchecked Sendable {
    private var current: Date

    init(now: Date = Date(timeIntervalSince1970: 1_784_376_000)) {
        self.current = now
    }

    func now() -> Date {
        current
    }

    func advance(by interval: TimeInterval) {
        current = current.addingTimeInterval(interval)
    }

    func set(_ date: Date) {
        current = date
    }
}
