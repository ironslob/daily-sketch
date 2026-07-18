import Foundation

protocol GuestTimerPreferenceStoring: Sendable {
    func load() -> TimerPreferenceOption?
    func save(_ option: TimerPreferenceOption?)
    func clear()
}

struct GuestTimerPreferenceStore: GuestTimerPreferenceStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "guest.remembered_timer_option"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TimerPreferenceOption? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return TimerPreferenceOption(rawValue: raw)
    }

    func save(_ option: TimerPreferenceOption?) {
        if let option {
            defaults.set(option.rawValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

final class InMemoryGuestTimerPreferenceStore: GuestTimerPreferenceStoring, @unchecked Sendable {
    private var option: TimerPreferenceOption?

    func load() -> TimerPreferenceOption? {
        option
    }

    func save(_ option: TimerPreferenceOption?) {
        self.option = option
    }

    func clear() {
        option = nil
    }
}
