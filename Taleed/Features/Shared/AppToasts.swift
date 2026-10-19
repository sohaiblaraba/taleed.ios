import Observation
import SwiftUI

/// The app's toasts, shown above the bottom navigation by the shell (decision D-11: dark toast for
/// feedback after an action). Screens read it with `@Environment(AppToasts.self)`.
@MainActor
@Observable
final class AppToasts {
    /// A screen that draws the tab bar itself (Item Detail), by its tab and its route.
    struct ScreenKey: Hashable {
        let tab: AppTab
        let route: AppRoute
    }

    let state = TaleedToastState()
    /// The height of the bottom bar of each screen that draws the tab bar itself (Item Detail): toasts
    /// show above the one of the screen on top. Measured per screen, since each listing has its own
    /// buttons (buyer, owner, sold), and kept while the screen stays in its stack.
    private(set) var screenBottomBarHeights: [ScreenKey: CGFloat] = [:]
    @ObservationIgnored private let languageManager: LanguageManager

    init(languageManager: LanguageManager) {
        self.languageManager = languageManager
    }

    func setBottomBarHeight(_ height: CGFloat, tab: AppTab, route: AppRoute) {
        let key = ScreenKey(tab: tab, route: route)
        if screenBottomBarHeights[key] != height { screenBottomBarHeights[key] = height }
    }

    /// The bottom bar of `route` on top of `tab`, if that screen measured one.
    func bottomBarHeight(tab: AppTab, route: AppRoute) -> CGFloat? {
        screenBottomBarHeights[ScreenKey(tab: tab, route: route)]
    }

    /// Forgets the screens that left their stack.
    func keepBottomBars(in paths: [AppTab: [AppRoute]]) {
        screenBottomBarHeights = screenBottomBarHeights.filter { paths[$0.key.tab]?.contains($0.key.route) == true }
    }

    /// `duration`: for a long message, how long it stays (the usual 4 s otherwise).
    func show(_ message: String, kind: TaleedFeedbackKind = .success, actionTitle: String? = nil,
              duration: TimeInterval? = nil, action: (() -> Void)? = nil) {
        state.show(ToastItem(kind: kind, message: message, actionTitle: actionTitle, onAction: action, duration: duration))
    }

    /// The app's message for a failed action (never the API's `message`).
    func show(error: ApiError) {
        show(languageManager.message(for: error), kind: .error)
    }
}
