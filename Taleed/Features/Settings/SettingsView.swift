import SwiftUI

/// Settings (screens.md §2 G16 and §7 G16; website `settings/page.tsx`; Figma does not draw it,
/// decision D-12): flat rows under eyebrows, as the Profile hub.
///
/// Signed in, in the website's order: the account (profile and billing, username, email, password,
/// identity verification), the newsletter switch, then the app-only sections: the language, the push switch (only with
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
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
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
        // The push permission may have changed in the system settings.
        .task { await push.refresh() }
        // Back in the foreground: the email may have been verified or changed meanwhile (slice E, Email).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, session.isSignedIn else { return }
            Task { await account.reload(automatic: true) }
            Task { await push.refresh() }
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
                ListRow(label: l10n.string(.settingsUsernameTitle), leadingIcon: .at,
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
                // The website's verification card, as its own screen (G17). The "Vérifié" badge once
                // verified (the profile hub's and the email screen's treatment).
                ListRow(label: l10n.string(.settingsVerificationTitle), leadingIcon: .sealCheck,
                        trailingBadge: profile.isVerified ? .verified(l10n.string(.profileVerified), size: .compact) : nil,
                        showsChevron: true) {
                    router.push(.identityVerification)
                }
                .accessibilityIdentifier("settings.verification")
                ListRow(label: l10n.string(.appSettingsAddressesTitle), leadingIcon: .mapPin, showsChevron: true) {
                    router.push(.addresses)
                }
                .accessibilityIdentifier("settings.addresses")
                ListRow(label: l10n.string(.appSettingsBlockedTitle), leadingIcon: .prohibit, showsChevron: true) {
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
            SettingsSkeletonRows(count: 7)
        }
    }

    /// The website's newsletter card: the switch changes at once and is disabled while it saves; on a
    /// failure it goes back, with `newsletter.error` (`AccountStore.setNewsletter`).
    @ViewBuilder
    private func newsletterSection(_ profile: AccountProfile) -> some View {
        SettingsEyebrow(text: l10n.string(.settingsNewsletterTitle))
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            Toggle(isOn: Binding(get: { account.newsletterPending ?? profile.newsletter }, set: { setNewsletter($0) })) {
                Text(l10n.string(.settingsNewsletterToggle))
            }
            .toggleStyle(.taleedRow)
            .disabled(account.newsletterPending != nil)
            .accessibilityIdentifier("settings.newsletter")
            FieldHelper(text: l10n.string(.settingsNewsletterDescription), color: TaleedColor.textSecondarySmall)
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    private func setNewsletter(_ isOn: Bool) {
        Task {
            if await !account.setNewsletter(isOn) { toasts.show(l10n.string(.settingsNewsletterError), kind: .error) }
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

    /// Only with `features.push` and a token: off unregisters this device, on registers it again. The
    /// switch shows the real state (the member's choice, the system permission, the registration); with
    /// the permission refused it says so and opens the system settings.
    @ViewBuilder
    private var pushSection: some View {
        SettingsEyebrow(text: l10n.string(.commonNotifications))
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Toggle(isOn: Binding(get: { pushPending ?? push.isSwitchedOn }, set: { setPush($0) })) {
                    Text(l10n.string(.pwaPushTitle))
                }
                .toggleStyle(.taleedRow)
                .disabled(pushPending != nil)
                .accessibilityIdentifier("settings.push")
                FieldHelper(text: l10n.string(.pwaPushBody), color: TaleedColor.textSecondarySmall)
            }
            if push.isPermissionDenied {
                InlineAlert(kind: .warning, title: l10n.string(.appSettingsPushDenied),
                            actionTitle: l10n.string(.appSettingsOpenSystemSettings), action: openSystemSettings)
                    .accessibilityIdentifier("settings.pushDenied")
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    private func setPush(_ isOn: Bool) {
        guard pushPending == nil else { return }
        pushPending = isOn
        Task {
            switch await push.setSwitchedOn(isOn) {
            case .done: break
            case .permissionDenied: toasts.show(l10n.string(.appSettingsPushDenied), kind: .error)
            case .failed: toasts.show(l10n.string(.commonErrorGeneric), kind: .error)
            }
            pushPending = nil
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    @ViewBuilder
    private var moreSection: some View {
        VStack(spacing: 0) {
            ListRow(label: l10n.string(.footerHelp), leadingIcon: .info, showsChevron: true) {
                router.push(.help)
            }
            .accessibilityIdentifier("settings.help")
            // "1.0.0 (1)" has no direction of its own: it stays left to right in Arabic too.
            ListRow(label: l10n.string(.settingsVersion), leadingIcon: .tag,
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

/// Placeholder rows while the account loads, drawn as the rows they stand for (the 20 pt icon and the
/// label at the list rows' margins and height), so nothing moves when the rows arrive.
struct SettingsSkeletonRows: View {
    let count: Int
    @Environment(LanguageManager.self) private var l10n
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20

    private static let widths: [CGFloat] = [72, 150, 120, 120, 170, 160, 140]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                VStack(spacing: 0) {
                    HStack(spacing: TaleedSpacing.s12) {
                        SkeletonBlock(width: min(iconSize, 36), height: min(iconSize, 36))
                        SkeletonBlock(width: Self.widths[index % Self.widths.count], height: 16)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, TaleedSpacing.s12)
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    Rectangle()
                        .fill(TaleedColor.borderSubtle)
                        .frame(height: 1)
                        .padding(.leading, TaleedLayout.screenMargin)
                }
            }
        }
        .skeletonPulse()
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
                TaleedIconView(.warningCircle, size: 20, color: TaleedColor.feedbackError)
                    .accessibilityHidden(true)
                Text(l10n.message(for: error))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // ErrorStateView's Retry (Outline Medium), so every error state retries the same way.
            TaleedButton(title: l10n.string(.commonRetry), kind: .outline, size: .medium, action: retry)
        }
        .padding(TaleedSpacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .taleedCard()
    }
}
