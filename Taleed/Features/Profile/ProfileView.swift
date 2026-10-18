import NukeUI
import SwiftUI

struct ProfileView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(ShellRouter.self) private var router

    var body: some View {
        List {
            if let user = session.user {
                Section { ProfileHeader(user: user) }
            } else {
                Section {
                    Button(l10n.string(.authSignIn)) { router.isSignInPresented = true }
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
                }
            }

            Section {
                NavigationLink(value: ProfileRoute.settings) {
                    Label(l10n.string(.settingsTitle), systemImage: "gearshape")
                        .frame(minHeight: Theme.minTouchTarget, alignment: .leading)
                }
            }

            if session.isSignedIn {
                Section {
                    Button(l10n.string(.authSignOut), role: .destructive) { session.signOut() }
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
                }
            }
        }
        .navigationTitle(l10n.string(.tabProfile))
    }
}

/// Avatar, `displayName`, `@username` when it differs, and the badge.
private struct ProfileHeader: View {
    let user: User
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: 16) {
            Avatar(url: user.avatarURL)
                .accessibilityLabel(l10n.string(.profileAvatar))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: user.displayName.isolatedByContent)
                    .font(.headline)
                if let handle = user.handle, handle != user.displayName {
                    Text(verbatim: handle.isolatedLeftToRight)
                        .foregroundStyle(.secondary)
                }
                if user.isOfficial {
                    Label(l10n.string(.profileOfficial), systemImage: "checkmark.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.primary)
                } else if user.isVerified {
                    Label(l10n.string(.profileVerified), systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct Avatar: View {
    let url: URL?
    private let size: CGFloat = 64

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityElement()
        .accessibilityAddTraits(.isImage)
    }
}
