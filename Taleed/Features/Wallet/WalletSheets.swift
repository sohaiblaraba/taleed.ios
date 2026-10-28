import SwiftUI

/// "Payout details" (slice H; the website's `PayoutAccountForm` dialog, drawn as the design-system bottom
/// sheet like the other forms): the purpose line, the method (from `GET /catalog` `payoutMethods`), the
/// account details with "Enter 5 to 300 characters." (red once out of bounds), and "Save", enabled once
/// they are valid. Only the method and the account details are asked. While saving, the sheet stays up
/// (no close, no swipe) and its fields are locked.
struct PayoutDetailsSheet: View {
    let methods: [CatalogOption]
    /// Saves the details; the owner closes the sheet on `.saved`.
    let save: (_ method: String, _ accountDetails: String) async -> WalletViewModel.SaveOutcome
    let onClose: () -> Void
    @State private var form: PayoutDetailsInput
    /// The API refused the details: shown until they change.
    @State private var detailsRefused = false
    @State private var isSaving = false
    @Environment(LanguageManager.self) private var l10n

    init(account: PayoutAccountInfo?, limits: WalletLimitsInfo, methods: [CatalogOption],
         save: @escaping (String, String) async -> WalletViewModel.SaveOutcome, onClose: @escaping () -> Void) {
        self.methods = methods
        self.save = save
        self.onClose = onClose
        _form = State(initialValue: PayoutDetailsInput(account: account, methods: methods.map(\.value), limits: limits))
    }

    var body: some View {
        TaleedBottomSheet(title: l10n.string(.walletPayoutDetailsTitle), onClose: onClose, isCloseHidden: isSaving) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                PayoutDetailsPurpose()
                VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
                    FieldLabel(text: l10n.string(.walletPayoutMethod), color: TaleedColor.textBody)
                    VStack(spacing: 0) {
                        ForEach(methods, id: \.value) { method in
                            TaleedRadio(title: method.label, isSelected: form.method == method.value) {
                                form.method = method.value
                            }
                            .accessibilityIdentifier("payoutDetails.method.\(method.value)")
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(l10n.string(.walletPayoutMethod))
                }
                TaleedTextArea(label: l10n.string(.walletAccountDetails), text: $form.accountDetails,
                               placeholder: l10n.string(.walletAccountDetailsPlaceholder),
                               helper: showsError ? nil : lengthText,
                               error: showsError ? lengthText : nil,
                               maxLength: form.inputLimit, textDirection: .leftToRight)
                    // An account number or a RIB: no autocorrection, spell check or capitals rewriting it.
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(isSaving)
                    .accessibilityIdentifier("payoutDetails.accountDetails")
                    .onChange(of: form.accountDetails) { _, _ in detailsRefused = false }
                TaleedButton(title: l10n.string(.walletPayoutDetailsSave), kind: .primary, size: .large, isLoading: isSaving,
                             isFullWidth: true, action: submit)
                    .disabled(!form.isValid || detailsRefused)
                    .accessibilityIdentifier("payoutDetails.save")
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var showsError: Bool { detailsRefused || form.showsLengthError }

    /// "Enter 5 to 300 characters."
    private var lengthText: String {
        l10n.format(.walletPayoutDetailsInvalid, form.minLength, form.maxLength)
    }

    private func submit() {
        guard form.isValid, !isSaving else { return }
        isSaving = true
        Task {
            let outcome = await save(form.method, form.trimmedDetails)
            isSaving = false
            if outcome == .detailsRefused { detailsRefused = true }
        }
    }
}
