import SwiftUI

struct ExploreView: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ShellScreen {
            ShellBrandAppBar()
        } content: {
            VStack(spacing: 0) {
                PageHeading(title: l10n.string(.tabExplore))
                MessageStateView(text: l10n.string(.searchPlaceholder), icon: .magnifyingGlass)
            }
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
                PageHeading(eyebrow: l10n.string(.tabSell), title: l10n.string(.tabSell))
                if session.isSignedIn {
                    MessageStateView(text: l10n.string(.sellPlaceholder), icon: .cloudArrowUp)
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
            ShellBrandAppBar()
        } content: {
            VStack(spacing: 0) {
                PageHeading(title: l10n.string(.tabMessages))
                if session.isSignedIn {
                    MessageStateView(text: l10n.string(.messagesPlaceholder), icon: .chatCircleText)
                } else {
                    SignInPromptView()
                }
            }
        }
    }
}
