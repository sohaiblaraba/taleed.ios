import SwiftUI

/// A settings screen that needs the account: the app bar, then the content once `GET /me` is there
/// (loading, or the error with Retry, offline included, before).
struct AccountScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: (AccountProfile) -> Content
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: title, onBack: { dismiss() })
        } content: {
            if let profile = store.profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                        content(profile)
                    }
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.vertical, TaleedSpacing.s16)
                }
                .scrollDismissesKeyboard(.interactively)
            } else if let error = store.loadError {
                ErrorStateView(error: error, retry: { Task { await store.retry() } }, onBack: { dismiss() })
            } else {
                LoadingStateView()
            }
        }
        .task { await store.loadIfNeeded() }
    }
}

/// A hint under a card's title (Body/Small, secondary).
private struct SettingsHint: View {
    let text: String

    var body: some View {
        Text(text)
            .taleedFont(TaleedFont.bodySmall)
            .foregroundStyle(TaleedColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Username

/// "Nom d'utilisateur": "@current", the website's hint, then the cooldown date in place of the field, or
/// "Nouveau nom d'utilisateur" with the rule and "Changer de nom d'utilisateur".
struct UsernameSettingsView: View {
    @State private var model: UsernameSettingsViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts

    init(api: AccountApi, store: AccountStore) {
        _model = State(initialValue: UsernameSettingsViewModel(api: api, store: store))
    }

    var body: some View {
        AccountScreen(title: l10n.string(.settingsUsernameTitle)) { profile in
            if let handle = profile.handle {
                Text(verbatim: handle.isolatedLeftToRight)
                    .taleedFont(TaleedFont.title2)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityIdentifier("username.current")
            }
            SettingsHint(text: l10n.string(.settingsUsernameChangeHint))
            if let date = model.lockedUntil {
                InlineAlert(kind: .info, title: cooldownText(date))
                    .accessibilityIdentifier("username.cooldown")
            } else {
                TaleedTextField(label: l10n.string(.settingsNewUsernameLabel),
                                text: Binding(get: { model.typed },
                                              set: { model.typed = AuthValidation.limited($0, to: AccountLimits.usernameMax) }),
                                helper: l10n.string(.settingsUsernameRuleHint), error: fieldError)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.done)
                    .onSubmit { Task { await model.submit() } }
                    .accessibilityIdentifier("username.field")
                TaleedButton(title: l10n.string(.settingsUsernameChangeCta), kind: .secondary, size: .large,
                             isLoading: model.isSending, isFullWidth: true) {
                    Task { await model.submit() }
                }
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("username.submit")
            }
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case let .changed(username): toasts.show(l10n.format(.settingsUsernameChanged, username))
            case let .error(error): toasts.show(error: error)
            }
        }
    }

    private var fieldError: String? {
        switch model.fieldError {
        case .rule?: l10n.string(.settingsUsernameRuleHint)
        case .same?: l10n.string(.settingsUsernameSameError)
        case .taken?: l10n.string(.settingsUsernameTakenError)
        case let .cooldown(date)?: date.map(cooldownText) ?? l10n.string(.appErrorUsernameCooldown)
        case nil: nil
        }
    }

    /// "Vous pourrez changer de nom d'utilisateur à partir du 19 nov. 2026."
    private func cooldownText(_ date: Date) -> String {
        l10n.format(.settingsUsernameCooldown, OrderText.date(date, locale: l10n.language.formattingLocale))
    }
}

// MARK: - Email

/// "Adresse email": the address with "Vérifiée" or "Non vérifiée"; when not verified, the reminder and
/// "Renvoyer l'email de vérification"; then the change, which sends a confirmation link.
struct EmailSettingsView: View {
    @State private var model: EmailSettingsViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts

    init(api: AccountApi, store: AccountStore) {
        _model = State(initialValue: EmailSettingsViewModel(api: api, store: store))
    }

    var body: some View {
        AccountScreen(title: l10n.string(.settingsEmailTitle)) { profile in
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                Text(verbatim: profile.email.isolatedLeftToRight)
                    .taleedFont(TaleedFont.bodyLarge)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityIdentifier("email.current")
                if profile.emailVerified {
                    TaleedBadge(title: l10n.string(.settingsEmailVerifiedBadge), tone: .brand, icon: .sealCheck)
                } else {
                    TaleedBadge(title: l10n.string(.settingsEmailNotVerifiedBadge), tone: .error, icon: .warningCircle)
                }
            }
            if !profile.emailVerified { verificationReminder }
            SectionBand().padding(.horizontal, -TaleedLayout.screenMargin)
            SettingsHint(text: l10n.string(.settingsEmailChangeHint))
            TaleedTextField(label: l10n.string(.settingsNewEmailLabel),
                            text: Binding(get: { model.typed },
                                          set: { model.typed = AuthValidation.limited($0, to: AccountLimits.emailMax) }),
                            error: fieldError)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { Task { await model.submit() } }
                .accessibilityIdentifier("email.field")
            if let sentTo = model.sentTo {
                InlineAlert(kind: .success, title: l10n.format(.settingsEmailChangeSent, sentTo.isolatedLeftToRight))
                    .accessibilityIdentifier("email.sent")
            }
            TaleedButton(title: l10n.string(.settingsEmailChangeCta), kind: .secondary, size: .large, isLoading: model.isSending,
                         isFullWidth: true) {
                Task { await model.submit() }
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("email.submit")
        }
        .onChange(of: model.notice) { _, error in
            guard let error else { return }
            model.notice = nil
            toasts.show(error: error)
        }
    }

    @ViewBuilder
    private var verificationReminder: some View {
        SettingsHint(text: l10n.string(.settingsEmailResendHint))
        if model.resent {
            InlineAlert(kind: .info, title: l10n.string(.settingsEmailResendSent))
                .accessibilityIdentifier("email.resent")
        } else {
            TaleedButton(title: l10n.string(.settingsEmailResendCta), kind: .outline, size: .medium, isLoading: model.isResending) {
                Task { await model.resend() }
            }
            .accessibilityIdentifier("email.resend")
        }
    }

    private var fieldError: String? {
        switch model.fieldError {
        case .invalid?: l10n.string(.appAuthEmailInvalid)
        case .same?: l10n.string(.settingsEmailSameError)
        case nil: nil
        }
    }
}

// MARK: - Password

/// "Mot de passe": the website's hint (the other devices will be signed out), the three fields and
/// "Changer le mot de passe".
struct PasswordSettingsView: View {
    @State private var model: PasswordSettingsViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts

    init(api: AccountApi) {
        _model = State(initialValue: PasswordSettingsViewModel(api: api))
    }

    var body: some View {
        AccountScreen(title: l10n.string(.settingsPasswordTitle)) { _ in
            SettingsHint(text: l10n.string(.settingsPasswordHint))
            field(.current, label: .settingsCurrentPasswordLabel, text: \.current, content: .password)
            field(.new, label: .settingsNewPasswordLabel, text: \.new, content: .newPassword)
            field(.confirm, label: .settingsConfirmPasswordLabel, text: \.confirm, content: .newPassword)
            TaleedButton(title: l10n.string(.settingsPasswordChangeCta), kind: .secondary, size: .large,
                         isLoading: model.isSending, isFullWidth: true) {
                Task { await model.submit() }
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("password.submit")
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case .changed: toasts.show(l10n.string(.appSettingsPasswordChanged))
            case let .error(error): toasts.show(error: error)
            }
        }
    }

    private func field(_ field: PasswordField, label: L10nKey, text: WritableKeyPath<PasswordForm, String>,
                       content: UITextContentType) -> some View {
        TaleedTextField(label: l10n.string(label),
                        text: Binding(get: { model.form[keyPath: text] },
                                      set: { model.form[keyPath: text] = AuthValidation.limited($0, to: AccountLimits.passwordMax + 1) }),
                        error: message(model.error(field)), isSecure: true)
            .textContentType(content)
            .accessibilityIdentifier("password.\(field)")
    }

    private func message(_ error: PasswordFieldError?) -> String? {
        switch error {
        case .tooShort?: l10n.string(.settingsPasswordTooShort)
        case .tooLong?: l10n.string(.appErrorPasswordTooLong)
        case .mismatch?: l10n.string(.settingsPasswordMismatch)
        case .wrong?: l10n.string(.settingsPasswordWrongError)
        case nil: nil
        }
    }
}
