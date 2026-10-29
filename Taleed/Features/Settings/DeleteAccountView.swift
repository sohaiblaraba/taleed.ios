import Observation
import SwiftUI

/// "Supprimer mon compte" (screens.md §2 G16 item 13 and §7 G16 "Delete account card"; slice E "Deleting
/// the account"; App Store guideline 5.1.1(v)). Also reachable from the suspended screen.
///
/// Screen 1 explains what is erased, what stays, and that it cannot be undone. Screen 2 is the website's
/// dialog: its title and text, the password, then `POST /me/delete`. What stops the deletion shows inside
/// the form as a red alert whose link opens the screen that solves it (the orders, Earnings), or with the
/// support contacts under it (an admin account or an amount owed to Taleed).
@MainActor
@Observable
final class DeleteAccountViewModel {
    enum Step {
        case explain, confirm
    }

    /// Whether the confirmation asks for the password (slice G, Members without a password).
    enum PasswordRequirement: Equatable {
        /// `hasPassword` true: the field, and the button waits for it.
        case required
        /// `hasPassword` false (Google or Apple only): no field, the body is `{}`.
        case none
        /// `GET /me` is not there (the suspended screen, where it answers `banned`, or still loading): the
        /// field shows but may stay empty. A member with a password who leaves it empty gets `wrong_password`.
        case optional

        init(hasPassword: Bool?) {
            switch hasPassword {
            case true?: self = .required
            case false?: self = .none
            case nil: self = .optional
            }
        }
    }

    /// Set by the screen from `GET /me`.
    var passwordRequirement = PasswordRequirement.required

    var step = Step.explain
    var password = "" {
        didSet { if password != oldValue, blocker == .wrongPassword { blocker = nil } }
    }

    private(set) var blocker: DeletionBlocker?
    private(set) var isDeleting = false

    @ObservationIgnored private let api: AccountApi
    /// Tells the three `wallet_not_empty` situations apart (slice H).
    @ObservationIgnored private let walletApi: WalletApi?
    @ObservationIgnored private let onDeleted: () -> Void

    init(api: AccountApi, walletApi: WalletApi? = nil, onDeleted: @escaping () -> Void) {
        self.api = api
        self.walletApi = walletApi
        self.onDeleted = onDeleted
    }

    /// "Oui, supprimer mon compte" stays disabled while a required password is empty.
    var canDelete: Bool {
        guard !isDeleting else { return false }
        return passwordRequirement != .required || !password.isEmpty
    }

    var showsPasswordField: Bool { passwordRequirement != .none }

    /// What `POST /me/delete` sends: nil (`{}`) without a password.
    var passwordToSend: String? {
        passwordRequirement == .none || password.isEmpty ? nil : password
    }

    func delete() async {
        guard canDelete else { return }
        blocker = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.deleteAccount(password: passwordToSend)
            onDeleted()
        } catch {
            // After a lost answer, `401` means the account is already gone (slice E, Retrying).
            if error == .unauthorized {
                onDeleted()
            } else if error.code == .walletNotEmpty {
                // Open to suspended members, like the deletion itself.
                let owed = try? await walletApi?.wallet(automatic: true).owed
                blocker = .walletNotEmpty(owed: owed)
            } else {
                blocker = DeletionBlocker(error)
            }
        }
    }
}

struct DeleteAccountView: View {
    @State private var model: DeleteAccountViewModel
    let store: AccountStore
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(LaunchViewModel.self) private var launch
    @Environment(\.dismiss) private var dismiss

    init(api: AccountApi, walletApi: WalletApi?, store: AccountStore, onDeleted: @escaping () -> Void) {
        self.store = store
        _model = State(initialValue: DeleteAccountViewModel(api: api, walletApi: walletApi, onDeleted: onDeleted))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.settingsDeleteTitle), onBack: back)
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                    switch model.step {
                    case .explain: explanation
                    case .confirm: confirmation
                    }
                }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.vertical, TaleedSpacing.s16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // `hasPassword` of `GET /me` decides the password field; a suspended member has no `GET /me`.
        .task { await store.loadIfNeeded() }
        .onChange(of: store.profile?.hasPassword, initial: true) { _, hasPassword in
            model.passwordRequirement = .init(hasPassword: hasPassword)
        }
    }

    /// Back from the password goes back to the explanation.
    private func back() {
        if model.step == .confirm, !model.isDeleting {
            model.step = .explain
        } else {
            dismiss()
        }
    }

    // MARK: Screen 1

    @ViewBuilder
    private var explanation: some View {
        // The same title style as step 2, so the two steps read as one flow.
        Text(l10n.string(.appSettingsDeleteIntroTitle))
            .taleedFont(TaleedFont.title2)
            .foregroundStyle(TaleedColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
        Text(l10n.string(.settingsDeleteHint))
            .taleedFont(TaleedFont.bodyRegular)
            .foregroundStyle(TaleedColor.textBody)
            .fixedSize(horizontal: false, vertical: true)
        section(.appSettingsDeleteErasedTitle, body: .appSettingsDeleteErasedBody)
        section(.appSettingsDeleteKeptTitle, body: .appSettingsDeleteKeptBody)
        InlineAlert(kind: .warning, title: l10n.string(.appSettingsDeleteIrreversible))
        TaleedButton(title: l10n.string(.appSettingsDeleteContinue), kind: .danger, size: .large, isFullWidth: true) {
            model.step = .confirm
        }
        .padding(.top, TaleedSpacing.s8)
        .accessibilityIdentifier("delete.continue")
    }

    private func section(_ title: L10nKey, body: L10nKey) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            SectionTitle(text: l10n.string(title))
            Text(l10n.string(body))
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, TaleedSpacing.s8)
    }

    // MARK: Screen 2

    @ViewBuilder
    private var confirmation: some View {
        Text(l10n.string(.settingsDeleteDialogTitle))
            .taleedFont(TaleedFont.title2)
            .foregroundStyle(TaleedColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
        Text(l10n.string(.settingsDeleteDialogBody))
            .taleedFont(TaleedFont.bodyRegular)
            .foregroundStyle(TaleedColor.textBody)
            .fixedSize(horizontal: false, vertical: true)
        if model.showsPasswordField {
            TaleedTextField(label: l10n.string(.settingsDeletePasswordLabel), text: $model.password,
                            error: model.blocker == .wrongPassword ? l10n.string(.settingsDeleteWrongPassword) : nil,
                            isSecure: true)
                .textContentType(.password)
                .submitLabel(.done)
                .accessibilityIdentifier("delete.password")
        }
        if let blocker = model.blocker, blocker != .wrongPassword {
            blockerView(blocker)
        }
        VStack(spacing: TaleedSpacing.s8) {
            // Always the filled red button, as Android (FB-13); the way out of a blocker is the alert's link.
            TaleedButton(title: l10n.string(.settingsDeleteConfirmCta), kind: .danger,
                         size: .large, isLoading: model.isDeleting, isFullWidth: true) {
                Task { await model.delete() }
            }
            .disabled(!model.canDelete)
            .accessibilityIdentifier("delete.confirm")
            TaleedButton(title: l10n.string(.settingsDeleteCancel), kind: .outline, size: .large, isFullWidth: true) {
                dismiss()
            }
            .disabled(model.isDeleting)
            .accessibilityIdentifier("delete.cancel")
        }
        .padding(.top, TaleedSpacing.s8)
    }

    /// What stops the deletion, as Android: the red alert with the next step as its link (the orders,
    /// Earnings), and for the support the contact rows under it.
    @ViewBuilder
    private func blockerView(_ blocker: DeletionBlocker) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            InlineAlert(kind: .error, title: message(blocker), actionTitle: remedyTitle(blocker.remedy),
                        action: remedyAction(blocker.remedy))
                .accessibilityIdentifier("delete.blocker")
            if blocker.remedy == .support, let support = launch.config?.support {
                SupportContactRows(support: support)
                    .taleedCard()
                    .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            }
        }
    }

    private func message(_ blocker: DeletionBlocker) -> String {
        l10n.string(blocker.messageKey)
    }

    private func remedyTitle(_ remedy: DeletionBlocker.Remedy?) -> String? {
        switch remedy {
        case .orders?: l10n.string(.appSettingsDeleteViewOrders)
        case .earnings?: l10n.string(.appSettingsDeleteViewEarnings)
        case .support?, nil: nil
        }
    }

    private func remedyAction(_ remedy: DeletionBlocker.Remedy?) -> (() -> Void)? {
        switch remedy {
        case .orders?: { router.push(.orders) }
        case .earnings?: { router.push(.wallet) }
        case .support?, nil: nil
        }
    }
}
