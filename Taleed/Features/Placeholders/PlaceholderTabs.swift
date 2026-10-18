import SwiftUI

struct ExploreView: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        MessageStateView(text: l10n.string(.searchPlaceholder))
            .navigationTitle(l10n.string(.tabExplore))
    }
}

struct SellView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session

    var body: some View {
        Group {
            if session.isSignedIn {
                MessageStateView(text: l10n.string(.sellPlaceholder))
            } else {
                SignInPromptView()
            }
        }
        .navigationTitle(l10n.string(.tabSell))
    }
}

struct MessagesView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session

    var body: some View {
        Group {
            if session.isSignedIn {
                MessageStateView(text: l10n.string(.messagesPlaceholder))
            } else {
                SignInPromptView()
            }
        }
        .navigationTitle(l10n.string(.tabMessages))
    }
}
