import Observation
import SwiftUI

/// The app's toasts, shown above the bottom navigation by the shell (decision D-11: dark toast for
/// feedback after an action). Screens read it with `@Environment(AppToasts.self)`.
@MainActor
@Observable
final class AppToasts {
    let state = TaleedToastState()
    @ObservationIgnored private let languageManager: LanguageManager

    init(languageManager: LanguageManager) {
        self.languageManager = languageManager
    }

    func show(_ message: String, kind: TaleedFeedbackKind = .success, actionTitle: String? = nil,
              action: (() -> Void)? = nil) {
        state.show(ToastItem(kind: kind, message: message, actionTitle: actionTitle, onAction: action))
    }

    /// The app's message for a failed action (never the API's `message`).
    func show(error: ApiError) {
        show(languageManager.message(for: error), kind: .error)
    }
}
