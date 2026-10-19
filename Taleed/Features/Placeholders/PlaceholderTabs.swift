import SwiftUI

// Tabs Figma does not draw (decision D-12) have the centred-title top app bar and a one-line message,
// as on Android (D7). Explore is in `Features/Explore`, Sell in `Features/Sell`, Messages in
// `Features/Messages`.

/// The notifications placeholder, pushed from the bell of the brand app bar (Home and Sell).
struct NotificationsView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.commonNotifications), onBack: { dismiss() })
        } content: {
            MessageStateView(text: l10n.string(.notificationsPlaceholder))
        }
    }
}
