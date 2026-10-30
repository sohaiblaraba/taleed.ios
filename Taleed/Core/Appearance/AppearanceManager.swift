import Foundation
import Observation
import SwiftUI
import UIKit

/// The app's colour schemes (design/dark-mode.md). System is the default: it follows the phone's setting,
/// live. Light and Dark override it.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let fallback: AppAppearance = .system

    var id: String { rawValue }

    /// Nil for System: SwiftUI then follows the phone and switches when the phone switches.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// `.unspecified` for System: the windows then inherit the phone's style instead of a copy read once.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// The choice's name in Settings.
    var titleKey: L10nKey {
        switch self {
        case .system: .appSettingsAppearanceSystem
        case .light: .appSettingsAppearanceLight
        case .dark: .appSettingsAppearanceDark
        }
    }
}

/// Stores and applies the Appearance setting. The choice is kept on the device (it survives sign-out
/// and is never sent to the server) and applies at once, without a restart: `preferredColorScheme` at
/// the root, and the windows' `overrideUserInterfaceStyle` for what UIKit presents (the in-app browser,
/// alerts, the keyboard).
@MainActor
@Observable
final class AppearanceManager {
    private(set) var appearance: AppAppearance

    @ObservationIgnored private let defaults: UserDefaults
    /// Applies the style to the app's windows. Tests replace it.
    @ObservationIgnored var applyToWindows: @MainActor (UIUserInterfaceStyle) -> Void = { AppearanceManager.applyToAllWindows($0) }
    static let storageKey = "app_appearance"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Self.resolve(stored: defaults.string(forKey: Self.storageKey))
    }

    /// The stored choice. No stored value, or an unknown one, means System; a stored Light or Dark is kept.
    nonisolated static func resolve(stored: String?) -> AppAppearance {
        stored.flatMap(AppAppearance.init(rawValue:)) ?? .fallback
    }

    /// The stored choice, for UIKit code that has no manager at hand (the in-app browser).
    static func storedAppearance(defaults: UserDefaults = .standard) -> AppAppearance {
        resolve(stored: defaults.string(forKey: storageKey))
    }

    /// Nil for System (follow the phone).
    var colorScheme: ColorScheme? { appearance.colorScheme }

    /// Stores the choice and applies it at once.
    func select(_ appearance: AppAppearance) {
        defaults.set(appearance.rawValue, forKey: Self.storageKey)
        guard appearance != self.appearance else { return }
        self.appearance = appearance
        apply()
    }

    /// Applies the current choice to the windows (at launch, once the window exists, and after a change).
    func apply() {
        applyToWindows(appearance.userInterfaceStyle)
    }

    private static func applyToAllWindows(_ style: UIUserInterfaceStyle) {
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
