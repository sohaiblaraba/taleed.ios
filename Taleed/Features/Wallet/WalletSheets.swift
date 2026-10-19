import SwiftUI

/// "Demander un virement" (screens.md §7 G14 "Payout dialog"; the website's dialog, drawn as the
/// design-system bottom sheet like the other forms): "Solde disponible: 3 095 DA", the amount prefilled
/// with the whole balance, the method (CCP by default), the account details, and "Envoyer la demande",
/// enabled once the three are valid. No confirmation step, as the website.
struct PayoutSheet: View {
    let summary: WalletSummary
    let methods: [CatalogOption]
    /// Sends the request; the owner closes the sheet on `.sent`.
    let submit: (_ amount: Int, _ method: String, _ accountDetails: String) async -> WalletViewModel.PayoutOutcome
    let onClose: () -> Void
    @State private var form: PayoutFormInput
    /// The API refused the amount (`insufficient_balance`): shown until it changes.
    @State private var amountRefused = false
    @State private var detailsRefused = false
    @State private var isSending = false
    @Environment(LanguageManager.self) private var l10n

    init(summary: WalletSummary, methods: [CatalogOption],
         submit: @escaping (Int, String, String) async -> WalletViewModel.PayoutOutcome, onClose: @escaping () -> Void) {
        self.summary = summary
        self.methods = methods
        self.submit = submit
        self.onClose = onClose
        let method = methods.contains { $0.value == PayoutFormInput.defaultMethod } ? PayoutFormInput.defaultMethod : methods.first?.value
        _form = State(initialValue: PayoutFormInput(balance: summary.balance, minPayout: summary.limits.minPayout,
                                                    method: method ?? PayoutFormInput.defaultMethod))
    }

    var body: some View {
        TaleedBottomSheet(title: l10n.string(.walletRequestPayout), onClose: onClose) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                // As the website's description: "Solde disponible: 3 095 DA".
                Text(verbatim: "\(l10n.string(.walletBalance)): \(PriceFormatter.format(summary.balance, language: l10n.language))")
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                    .accessibilityIdentifier("payout.balance")
                TaleedTextField(label: l10n.string(.walletPayoutAmount), text: $form.amountText, leadingIcon: .money,
                                helper: amountHelper, error: amountError)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("payout.amount")
                    .onChange(of: form.amountText) { _, value in
                        let digits = OfferAmountInput.normalizedDigits(value)
                        if digits != value { form.amountText = digits }
                        amountRefused = false
                    }
                VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
                    FieldLabel(text: l10n.string(.walletPayoutMethod), color: TaleedColor.textBody)
                    VStack(spacing: 0) {
                        ForEach(methods, id: \.value) { method in
                            TaleedRadio(title: method.label, isSelected: form.method == method.value) {
                                form.method = method.value
                            }
                            .accessibilityIdentifier("payout.method.\(method.value)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(l10n.string(.walletPayoutMethod))
                }
                TaleedTextArea(label: l10n.string(.walletAccountDetails), text: $form.accountDetails,
                               placeholder: l10n.string(.walletAccountDetailsPlaceholder),
                               helper: detailsRefused ? nil : detailsHelper,
                               error: detailsRefused ? l10n.string(.appCheckoutFieldInvalid) : nil)
                    .accessibilityIdentifier("payout.details")
                    .onChange(of: form.accountDetails) { _, value in
                        if value.count > PayoutFormInput.detailsMaxLength {
                            form.accountDetails = String(value.prefix(PayoutFormInput.detailsMaxLength))
                        }
                        detailsRefused = false
                    }
                TaleedButton(title: l10n.string(.walletSubmitPayout), kind: .primary, size: .large, isLoading: isSending,
                             isFullWidth: true, action: send)
                    .disabled(!form.isValid || amountRefused)
                    .accessibilityIdentifier("payout.submit")
            }
        }
        // A refused amount reloads the header: the form follows the new balance.
        .onChange(of: summary.balance) { _, balance in form.balance = balance }
    }

    /// "Le montant doit être compris entre 100 DA et 3 095 DA."
    private var amountHelper: String? {
        guard let range = form.amountRange else { return nil }
        return l10n.format(.appWalletAmountRange, PriceFormatter.format(range.lowerBound, language: l10n.language),
                           PriceFormatter.format(range.upperBound, language: l10n.language))
    }

    /// "Montant invalide ou supérieur au solde disponible." once the amount is out of range or refused.
    private var amountError: String? {
        amountRefused || form.amount == .invalid ? l10n.string(.walletErrorAmount) : nil
    }

    private var detailsHelper: String {
        l10n.format(.appAuthNameLength, PayoutFormInput.detailsMinLength, PayoutFormInput.detailsMaxLength)
    }

    private func send() {
        guard let amount = form.amount.amount, form.isValid, !isSending else { return }
        isSending = true
        Task {
            let outcome = await submit(amount, form.method, form.trimmedDetails)
            isSending = false
            switch outcome {
            case .amountRefused: amountRefused = true
            case .detailsRefused: detailsRefused = true
            case .sent, .failed: break
            }
        }
    }
}

/// "Recharger le solde" (screens.md §7 G14 "Top-up dialog"): the website's text, the amount prefilled with
/// 1 000 DA, the gateways as radio cards only when there is more than one, and "Procéder au paiement",
/// which reads "Redirection vers le paiement…" while the top-up starts.
struct TopUpSheet: View {
    let summary: WalletSummary
    let isStarting: Bool
    let start: (_ amount: Int, _ method: String) async -> Void
    let onClose: () -> Void
    @State private var form: TopUpFormInput
    @Environment(LanguageManager.self) private var l10n

    init(summary: WalletSummary, isStarting: Bool, start: @escaping (Int, String) async -> Void, onClose: @escaping () -> Void) {
        self.summary = summary
        self.isStarting = isStarting
        self.start = start
        self.onClose = onClose
        _form = State(initialValue: TopUpFormInput(limits: summary.limits, methods: summary.topUpMethods))
    }

    var body: some View {
        TaleedBottomSheet(title: l10n.string(.walletTopUpTitle), onClose: onClose) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                Text(l10n.string(.walletTopUpBody))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                TaleedTextField(label: l10n.string(.walletTopUpAmount), text: $form.amountText, leadingIcon: .money,
                                helper: form.amount == .invalid ? nil : rangeText,
                                error: form.amount == .invalid ? rangeText : nil)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("topUp.amount")
                    .onChange(of: form.amountText) { _, value in
                        let digits = OfferAmountInput.normalizedDigits(value)
                        if digits != value { form.amountText = digits }
                    }
                if WalletRules.showsTopUpMethodPicker(summary) {
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        FieldLabel(text: l10n.string(.checkoutPaymentMethod), color: TaleedColor.textBody)
                        ForEach(summary.topUpMethods) { method in
                            DeliveryOption(icon: .lockKey, title: method.label, description: method.hint,
                                           selected: form.method == method.value) {
                                form.method = method.value
                            }
                            .accessibilityIdentifier("topUp.method.\(method.value)")
                        }
                    }
                }
                TaleedButton(title: l10n.string(isStarting ? .checkoutProcessing : .walletTopUpSubmit), kind: .secondary,
                             size: .large, leadingIcon: .lockKey, isFullWidth: true,
                             forcedState: isStarting ? .normal : nil, action: submit)
                    .disabled(!form.isValid)
                    .allowsHitTesting(!isStarting)
                    .accessibilityIdentifier("topUp.submit")
            }
        }
    }

    /// "Le montant doit être compris entre 100 DA et 1 000 000 DA."
    private var rangeText: String? {
        guard let range = form.amountRange else { return nil }
        return l10n.format(.appWalletAmountRange, PriceFormatter.format(range.lowerBound, language: l10n.language),
                           PriceFormatter.format(range.upperBound, language: l10n.language))
    }

    private func submit() {
        guard let amount = form.amount.amount, let method = form.method, !isStarting else { return }
        Task { await start(amount, method) }
    }
}
