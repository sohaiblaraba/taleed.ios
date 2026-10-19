import SwiftUI

// Tabs Figma does not draw (decision D-12) have the centred-title top app bar and a one-line message,
// as on Android (D7). Sell keeps the wireframe's brand app bar and page heading.

struct ExploreView: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.tabExplore))
        } content: {
            MessageStateView(text: l10n.string(.searchPlaceholder))
        }
    }
}

struct SellView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session

    var body: some View {
        ShellScreen {
            ShellBrandAppBar()
        } content: {
            VStack(spacing: 0) {
                PageHeading(eyebrow: l10n.string(.tabSell), title: l10n.string(.sellTitle))
                if session.isSignedIn {
                    MessageStateView(text: l10n.string(.sellPlaceholder))
                } else {
                    SignInPromptView()
                }
            }
        }
    }
}

struct MessagesView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.tabMessages))
        } content: {
            if session.isSignedIn {
                MessageStateView(text: l10n.string(.messagesPlaceholder))
            } else {
                SignInPromptView()
            }
        }
    }
}

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
