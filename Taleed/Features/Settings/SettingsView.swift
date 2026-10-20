import SwiftUI

/// Settings (screens.md §2 G16 and §7 G16; website `settings/page.tsx`; Figma does not draw it,
/// decision D-12): flat rows under eyebrows, as the Profile hub.
///
/// Signed in, in the website's order: the account (profile and billing, username, email, password), the
/// newsletter switch, then the app-only sections: the language, the push switch (only with
/// `features.push`), saved addresses, blocked members, help and the version, "Se déconnecter" and, at
/// the bottom, "Supprimer mon compte". Signed out: the language, help and the version.
///
/// The account rows wait for `GET /me` (skeleton rows, or the error with Retry, offline included); the
/// language, help and sign-out work without it.
struct SettingsView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var session
    @Environment(AccountStore.self) private var account
    @Environment(PushRegistration.self) private var push
    @Environment(AppToasts.self) private var toasts
    @Environment(\.settingsDependencies) private var dependencies
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The newsletter switch while its change is on its way (optimistic, as the website's).
    @State private var newsletterPending: Bool?
    @State private var pushPending: Bool?

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.settingsTitle), onBack: { dismiss() })
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if session.isSignedIn { accountSection }
                    languageSection
                    if session.isSignedIn, push.canBeSwitched { pushSection }
                    moreSection
                    if session.isSignedIn { signOutAndDelete }
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
            .refreshable { await account.reload() }
            .accessibilityIdentifier("settings.scroll")
        }
        .task(id: session.user?.id) { await account.loadIfNeeded() }
        // Back in the foreground: the email may have been verified or changed meanwhile (slice E, Email).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, session.isSignedIn { Task { await account.reload(automatic: true) } }
        }
    }

    // MARK: Account

    @ViewBuilder
    private var accountSection: some View {
        SettingsEyebrow(text: l10n.string(.appSettingsAccount))
        if let profile = account.profile {
            VStack(spacing: 0) {
                ListRow(label: l10n.string(.settingsProfile), leadingIcon: .user, showsChevron: true) {
                    router.push(.profileSettings)
                }
                .accessibilityIdentifier("settings.profile")
                ListRow(label: l10n.string(.settingsUsernameTitle), leadingIcon: .sealCheck,
                        trailingText: profile.handle?.isolatedLeftToRight, showsChevron: true) {
                    router.push(.usernameSettings)
                }
                .accessibilityIdentifier("settings.username")
                ListRow(label: l10n.string(.settingsEmailTitle), leadingIcon: .envelope,
                        trailingText: profile.emailVerified ? nil : l10n.string(.settingsEmailNotVerifiedBadge),
                        showsChevron: true) {
                    router.push(.emailSettings)
                }
                .accessibilityIdentifier("settings.email")
                ListRow(label: l10n.string(.settingsPasswordTitle), leadingIcon: .lockKey, showsChevron: true) {
                    router.push(.passwordSettings)
                }
                .accessibilityIdentifier("settings.password")
                ListRow(label: l10n.string(.appSettingsAddressesTitle), leadingIcon: .mapPin, showsChevron: true) {
                    router.push(.addresses)
                }
                .accessibilityIdentifier("settings.addresses")
                ListRow(label: l10n.string(.appSettingsBlockedTitle), leadingIcon: .shieldCheck, showsChevron: true) {
                    router.push(.blockedMembers)
                }
                .accessibilityIdentifier("settings.blocked")
            }
            newsletterSection(profile)
        } else if let error = account.loadError {
            InlineErrorRetry(error: error) { Task { await account.retry() } }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.bottom, TaleedSpacing.s8)
        } else {
            SettingsSkeletonRows(count: 6)
        }
    }

    /// The website's newsletter card: the switch changes at once and is disabled while it saves; on a
    /// failure it goes back, with `newsletter.error`.
    @ViewBuilder
    private func newsletterSection(_ profile: AccountProfile) -> some View {
        SettingsEyebrow(text: l10n.string(.settingsNewsletterTitle))
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            Toggle(isOn: Binding(get: { newsletterPending ?? profile.newsletter }, set: { setNewsletter($0) })) {
                Text(l10n.string(.settingsNewsletterToggle))
            }
            .toggleStyle(.taleed)
            .disabled(newsletterPending != nil)
            .accessibilityIdentifier("settings.newsletter")
            FieldHelper(text: l10n.string(.settingsNewsletterDescription), color: TaleedColor.textSecondary)
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    private func setNewsletter(_ isOn: Bool) {
        guard newsletterPending == nil, let api = dependencies?.account else { return }
        newsletterPending = isOn
        Task {
            do {
                account.apply(try await api.setNewsletter(isOn))
            } catch {
                toasts.show(l10n.string(.settingsNewsletterError), kind: .error)
            }
            newsletterPending = nil
        }
    }

    // MARK: App

    @ViewBuilder
    private var languageSection: some View {
        SettingsEyebrow(text: l10n.string(.settingsLanguage))
        VStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { language in
                // Each name in its own language.
                TaleedRadio(title: language.nativeName, isSelected: language == l10n.language) {
                    l10n.select(language)
                }
                .environment(\.locale, language.locale)
                .accessibilityIdentifier("settings.language.\(language.rawValue)")
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    /// Only with `features.push` and a token: off unregisters this device, on registers it again.
    @ViewBuilder
    private var pushSection: some View {
        SettingsEyebrow(text: l10n.string(.commonNotifications))
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            Toggle(isOn: Binding(get: { pushPending ?? push.isSwitchedOn }, set: { setPush($0) })) {
                Text(l10n.string(.pwaPushTitle))
            }
            .toggleStyle(.taleed)
            .disabled(pushPending != nil)
            FieldHelper(text: l10n.string(.pwaPushBody), color: TaleedColor.textSecondary)
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    private func setPush(_ isOn: Bool) {
        guard pushPending == nil else { return }
        pushPending = isOn
        Task {
            if await !push.setSwitchedOn(isOn) { toasts.show(l10n.string(.commonErrorGeneric), kind: .error) }
            pushPending = nil
        }
    }

    @ViewBuilder
    private var moreSection: some View {
        VStack(spacing: 0) {
            ListRow(label: l10n.string(.footerHelp), leadingIcon: .info, showsChevron: true) {
                router.push(.help)
            }
            .accessibilityIdentifier("settings.help")
            // "1.0.0 (1)" has no direction of its own: it stays left to right in Arabic too.
            ListRow(label: l10n.string(.settingsVersion),
                    trailingText: "\(environment.appVersion) (\(environment.buildNumber))".isolatedLeftToRight)
            #if DEBUG
            ListRow(label: "Design system", leadingIcon: .sparkle, showsChevron: true) {
                router.push(.designSystem)
            }
            ListRow(label: "Developer menu", leadingIcon: .info, showsChevron: true) {
                router.push(.developerMenu)
            }
            #endif
        }
        .padding(.top, TaleedSpacing.s16)
    }

    /// "Se déconnecter", then "Supprimer mon compte" at the very bottom, in red as on the suspended screen.
    private var signOutAndDelete: some View {
        VStack(spacing: TaleedSpacing.s24) {
            TaleedButton(title: l10n.string(.authSignOut), kind: .tertiary, size: .large, isFullWidth: true) {
                // `POST /auth/sign-out`, and the token goes whatever the answer.
                session.signOut()
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .accessibilityIdentifier("settings.signOut")
            ListRow(label: l10n.string(.settingsDeleteCta), leadingIcon: .trash, showsChevron: true, showsDivider: false,
                    labelColor: TaleedColor.feedbackError) {
                router.push(.deleteAccount)
            }
            .accessibilityIdentifier("settings.delete")
        }
        .padding(.top, TaleedSpacing.s24)
    }
}

// MARK: - Shared pieces

/// A group title of the settings screens: the eyebrow, padded as the hub's rows.
struct SettingsEyebrow: View {
    let text: String

    var body: some View {
        Eyebrow(text: text)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.top, TaleedSpacing.s24)
            .padding(.bottom, TaleedSpacing.s8)
    }
}

/// Placeholder rows while the account loads.
struct SettingsSkeletonRows: View {
    let count: Int
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonBlock(width: 180, height: 16)
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.vertical, TaleedSpacing.s16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(.commonLoading))
    }
}

/// An error inside a screen that keeps the rest (the hub's account rows): the message and "Réessayer".
struct InlineErrorRetry: View {
    let error: ApiError
    let retry: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            HStack(alignment: .top, spacing: TaleedSpacing.s8) {
                TaleedIconView(error == .network ? .wifiHigh : .warningCircle, size: 20,
                               color: error == .network ? TaleedColor.textSecondary : TaleedColor.feedbackError)
                    .accessibilityHidden(true)
                Text(l10n.message(for: error))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TaleedButton(title: l10n.string(.commonRetry), kind: .tertiary, size: .medium, action: retry)
        }
        .padding(TaleedSpacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .taleedCard()
    }
}
