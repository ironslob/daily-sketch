import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppearanceStore {
    var preference: String = UserPreferencesModel.defaults.appearance

    var colorScheme: ColorScheme? {
        switch preference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    func update(from preferences: UserPreferencesModel) {
        preference = preferences.appearance
    }
}

enum AppearancePreferenceMapper {
    static func colorScheme(for appearance: String) -> ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
