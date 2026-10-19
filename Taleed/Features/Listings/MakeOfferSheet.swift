import SwiftUI

/// "Faire une offre" (screens.md §7 G4, §2 G10 screen 1; website `listing-actions.tsx`): the hint
/// "Prix affiché : {price}…", the amount in DA with the server's bounds under it, and "Envoyer l'offre".
/// An amount outside `offerRange` shows `offers.errorRange` before anything is sent.
struct MakeOfferSheet: View {
    let price: Int
    @State var range: AmountRange
    /// Sends the amount; the sheet acts on the answer (`ListingDetailViewModel.makeOffer`).
    let send: (Int) async -> ListingDetailViewModel.OfferOutcome
    /// The sheet is done: close it and continue with the outcome (toast, conversation).
    let onFinish: (ListingDetailViewModel.OfferOutcome) -> Void
    @State private var text = ""
    @State private var showsRangeError = false
    @State private var isSending = false
    @FocusState private var isFocused: Bool
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        TaleedBottomSheet(title: l10n.string(.offersMakeOffer), onClose: { onFinish(.busy) }, content: {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                Text(l10n.format(.offersOfferHint, PriceFormatter.format(price, language: l10n.language)))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                TaleedTextField(label: l10n.string(.offersOfferAmount), text: $text, placeholder: "",
                                leadingIcon: .money, helper: showsRangeError ? nil : rangeText,
                                error: showsRangeError ? rangeText : nil, focus: $isFocused)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("offer.amount")
                    .onChange(of: text) { _, value in
                        let digits = OfferAmountInput.normalizedDigits(value)
                        if digits != value { text = digits }
                        showsRangeError = false
                    }
                TaleedButton(title: l10n.string(.offersSendOffer), kind: .primary, size: .large, isLoading: isSending,
                             isFullWidth: true, action: submit)
                    .disabled(input == .empty)
                    .accessibilityIdentifier("offer.send")
            }
        })
        .onAppear { isFocused = true }
    }

    private var input: OfferAmountInput { OfferAmountInput(text: text, range: range) }

    /// "L'offre doit être comprise entre 750 DA et 2 500 DA." under the field: the bounds, in red once
    /// an amount outside them was sent.
    private var rangeText: String {
        l10n.format(.offersErrorRange, PriceFormatter.format(range.min, language: l10n.language),
                    PriceFormatter.format(range.max, language: l10n.language))
    }

    private func submit() {
        guard case let .valid(amount) = input else {
            showsRangeError = true
            return
        }
        isSending = true
        Task {
            let outcome = await send(amount)
            isSending = false
            switch outcome {
            case let .outOfRange(newRange?):
                // The price changed: the new bounds, in red.
                range = newRange
                showsRangeError = true
            case .busy:
                break
            case .sent, .pending, .outOfRange(nil), .failed:
                onFinish(outcome)
            }
        }
    }
}
