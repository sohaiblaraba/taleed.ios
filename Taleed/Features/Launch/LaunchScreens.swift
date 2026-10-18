import SwiftUI

/// Shown while the launch flow runs.
struct SplashView: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: 16) {
            Text(l10n.string(.appName))
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.primary)
            ProgressView()
                .accessibilityLabel(l10n.string(.commonLoading))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The launch could not finish (no network, server error). The token, if any, is kept.
struct LaunchErrorView: View {
    let error: ApiError
    let retry: () -> Void

    var body: some View {
        ErrorStateView(error: error, retry: retry)
    }
}

/// Blocking: the app is below `minimumVersion.ios`.
struct UpdateRequiredView: View {
    let storeURL: URL
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.app")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
                Text(l10n.string(.updateRequiredTitle))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(l10n.string(.updateRequiredBody))
                    .multilineTextAlignment(.center)
                Button(l10n.string(.updateRequiredAction)) { openURL(storeURL) }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: Theme.minTouchTarget)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
    }
}

/// The account is suspended: support contacts from `GET /config`, and Sign out.
struct SuspendedView: View {
    let support: SupportContacts
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.string(.suspendedTitle))
                        .font(.title2.bold())
                    Text(l10n.string(.suspendedBody))
                }
                .padding(.vertical, 8)
            }

            Section(l10n.string(.suspendedContact)) {
                if let url = URL(string: "mailto:\(support.email)") {
                    contactLink(support.email, systemImage: "envelope", url: url)
                }
                if let url = URL(string: "tel:\(support.phone.filter { !$0.isWhitespace })") {
                    contactLink(support.phone, systemImage: "phone", url: url)
                }
                if let url = support.whatsappURL {
                    contactLink("WhatsApp", systemImage: "message", url: url)
                }
            }

            Section {
                Button(l10n.string(.authSignOut), role: .destructive) { session.signOut() }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
            }
        }
    }

    private func contactLink(_ title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            Label {
                // Emails and phone numbers read left to right in Arabic too.
                Text(verbatim: title).environment(\.layoutDirection, .leftToRight)
            } icon: {
                Image(systemName: systemImage)
            }
            .frame(minHeight: Theme.minTouchTarget, alignment: .leading)
        }
    }
}
