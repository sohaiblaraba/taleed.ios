import Observation
import SwiftUI

/// "Supprimer mon compte" (screens.md §2 G16 item 13 and §7 G16 "Delete account card"; slice E "Deleting
/// the account"; App Store guideline 5.1.1(v)). Also reachable from the suspended screen.
///
/// Screen 1 explains what is erased, what stays, and that it cannot be undone. Screen 2 is the website's
/// dialog: its title and text, the password, then `POST /me/delete`. What stops the deletion shows inside
/// the form with the way to the screen that solves it (the orders, the wallet, the payout form, the
/// support contacts for an admin account).
@MainActor
@Observable
final class DeleteAccountViewModel {
    enum Step {
        case explain, confirm
    }

    var step = Step.explain
    var password = "" {
        didSet { if password != oldValue, blocker == .wrongPassword { blocker = nil } }
    }

    private(set) var blocker: DeletionBlocker?
    private(set) var isDeleting = false

    @ObservationIgnored private let api: AccountApi
    @ObservationIgnored private let onDeleted: () -> Void

    init(api: AccountApi, onDeleted: @escaping () -> Void) {
        self.api = api
        self.onDeleted = onDeleted
    }

    /// "Oui, supprimer mon compte" stays disabled while the password is empty.
    var canDelete: Bool { !password.isEmpty && !isDeleting }

    func delete() async {
        guard canDelete else { return }
        blocker = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.deleteAccount(password: password)
            onDeleted()
        } catch {
            // After a lost answer, `401` means the account is already gone (slice E, Retrying).
            if error == .unauthorized {
                onDeleted()
            } else {
                blocker = DeletionBlocker(error)
            }
        }
    }
}

struct DeleteAccountView: View {
    @State private var model: DeleteAccountViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(LaunchViewModel.self) private var launch
    @Environment(\.dismiss) private var dismiss

    init(api: AccountApi, onDeleted: @escaping () -> Void) {
        _model = State(initialValue: DeleteAccountViewModel(api: api, onDeleted: onDeleted))
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
        TaleedTextField(label: l10n.string(.settingsDeletePasswordLabel), text: $model.password,
                        error: model.blocker == .wrongPassword ? l10n.string(.settingsDeleteWrongPassword) : nil, isSecure: true)
            .textContentType(.password)
            .submitLabel(.done)
            .accessibilityIdentifier("delete.password")
        if let blocker = model.blocker, blocker != .wrongPassword {
            blockerView(blocker)
        }
        VStack(spacing: TaleedSpacing.s8) {
            TaleedButton(title: l10n.string(.settingsDeleteConfirmCta), kind: .danger, size: .large, isLoading: model.isDeleting,
                         isFullWidth: true) {
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

    @ViewBuilder
    private func blockerView(_ blocker: DeletionBlocker) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
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
        switch blocker {
        case .wrongPassword: l10n.string(.settingsDeleteWrongPassword)
        case .activeOrders: l10n.string(.settingsDeleteBlockedActiveOrders)
        case .openDispute: l10n.string(.settingsDeleteBlockedOpenDisputes)
        case .pendingPayout: l10n.string(.settingsDeleteBlockedPendingPayout)
        case .walletNotEmpty: l10n.string(.settingsDeleteBlockedWallet)
        case .admin: l10n.string(.settingsDeleteBlockedAdmin)
        case .tooManyAttempts: l10n.string(.settingsDeleteTooManyAttempts)
        case .network: l10n.string(.commonErrorNetwork)
        case .generic: l10n.string(.settingsDeleteBlockedGeneric)
        }
    }

    private func remedyTitle(_ remedy: DeletionBlocker.Remedy?) -> String? {
        switch remedy {
        case .orders?: l10n.string(.navOrders)
        case .wallet?: l10n.string(.navWallet)
        case .payout?: l10n.string(.walletRequestPayout)
        case .support?, nil: nil
        }
    }

    private func remedyAction(_ remedy: DeletionBlocker.Remedy?) -> (() -> Void)? {
        switch remedy {
        case .orders?: { router.push(.orders) }
        case .wallet?: { router.push(.wallet) }
        case .payout?: { router.push(.walletPayout) }
        case .support?, nil: nil
        }
    }
}
