import SwiftUI

/// The amount sheet of every offer (screens.md §2 G10; Figma Item Detail "Make an offer" and the
/// design-system bottom sheet): a title, a hint, the amount in DA with the server's bounds under it, and
/// "Envoyer l'offre". An amount outside the bounds shows `offers.errorRange` in red before anything is
/// sent; an `offer_out_of_range` answer shows the new bounds the same way.
///
/// Used for an offer on a listing (`MakeOfferSheet`), in a conversation ("Faire une offre" / "Proposer un
/// prix"), for a counter-offer and for an offer on a bundle.
struct OfferAmountSheet: View {
    let title: String
    let hint: String?
    @State var range: AmountRange
    /// Sends the amount and says what the sheet does next. The owner closes the sheet on `.finish`.
    let submit: (Int) async -> OfferSheetStep
    let onClose: () -> Void
    @State private var text: String
    @State private var showsRangeError = false
    @State private var isSending = false
    @FocusState private var isFocused: Bool
    @Environment(LanguageManager.self) private var l10n

    init(title: String, hint: String?, range: AmountRange, initialAmount: Int? = nil,
         submit: @escaping (Int) async -> OfferSheetStep, onClose: @escaping () -> Void) {
        self.title = title
        self.hint = hint
        _range = State(initialValue: range)
        self.submit = submit
        self.onClose = onClose
        _text = State(initialValue: initialAmount.map(String.init) ?? "")
    }

    var body: some View {
        TaleedBottomSheet(title: title, onClose: onClose, content: {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                if let hint {
                    Text(hint)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TaleedTextField(label: l10n.string(.offersOfferAmount), text: $text,
                                placeholder: PriceFormatter.number(Self.example(in: range), language: l10n.language),
                                leadingIcon: .money, helper: showsRangeError ? nil : rangeText,
                                error: showsRangeError ? rangeText : nil, focus: $isFocused)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("offer.amount")
                    .onChange(of: text) { _, value in
                        // Grouped as the bounds under it ("3 500", Arabic "3.500"); only the digits count.
                        let shown = Self.grouped(value, language: l10n.language)
                        if shown != value { text = shown }
                        showsRangeError = false
                    }
                TaleedButton(title: l10n.string(.offersSendOffer), kind: .primary, size: .large, isLoading: isSending,
                             isFullWidth: true, action: send)
                    .disabled(input == .empty)
                    .accessibilityIdentifier("offer.send")
            }
        })
        .onAppear {
            text = Self.grouped(text, language: l10n.language)
            isFocused = true
        }
    }

    private var input: OfferAmountInput { OfferAmountInput(text: text, range: range) }

    /// The typed digits grouped by thousands in the app language; empty without digits.
    static func grouped(_ text: String, language: AppLanguage) -> String {
        let digits = OfferAmountInput.normalizedDigits(text)
        guard let value = Int(digits) else { return "" }
        return PriceFormatter.number(value, language: language)
    }

    /// The placeholder's example: the middle of the bounds, rounded to the hundred, kept inside them.
    static func example(in range: AmountRange) -> Int {
        let middle = (Double(range.min + range.max) / 2 / 100).rounded() * 100
        return min(max(Int(middle), range.min), range.max)
    }

    /// "L'offre doit être comprise entre 750 DA et 2 500 DA." under the field: the bounds, in red once
    /// an amount outside them was sent.
    private var rangeText: String {
        l10n.format(.offersErrorRange, PriceFormatter.format(range.min, language: l10n.language),
                    PriceFormatter.format(range.max, language: l10n.language))
    }

    private func send() {
        guard case let .valid(amount) = input else {
            showsRangeError = true
            return
        }
        isSending = true
        Task {
            let step = await submit(amount)
            isSending = false
            if case let .showRange(newRange) = step {
                range = newRange
                showsRangeError = true
            }
        }
    }
}
