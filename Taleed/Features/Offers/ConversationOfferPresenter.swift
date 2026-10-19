import SwiftUI

/// An offer sheet of the conversation screen (G10).
enum ConversationOfferSheet: Identifiable, Equatable {
    /// "Faire une offre" (buyer) or "Proposer un prix" (seller): bounded by the conversation's `offerRange`.
    case make(ConversationOfferEntry, range: AmountRange, price: Int?)
    /// "Contre-offre" to this offer, bounded by its `counterRange`.
    case counter(ChatOffer)

    var id: String {
        switch self {
        case .make: "make"
        case let .counter(offer): "counter-\(offer.id)"
        }
    }

    /// The make-offer sheet for the conversation as it stands, nil when no offer can be made.
    @MainActor
    static func make(for model: ConversationViewModel) -> ConversationOfferSheet? {
        guard let entry = model.offerEntry, let range = model.conversation?.offerRange else { return nil }
        return .make(entry, range: range, price: model.conversation?.listing?.price)
    }
}

extension ConversationOfferEntry {
    var titleKey: L10nKey {
        switch self {
        case .makeOffer: .offersMakeOffer
        case .proposePrice: .chatProposePrice
        }
    }
}

/// The offer sheets and the "Accepter" confirmation of the conversation screen (G10).
struct ConversationOfferPresenter: ViewModifier {
    let model: ConversationViewModel
    let counterpartName: String?
    @Binding var sheet: ConversationOfferSheet?
    @Binding var accepting: ChatOffer?
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .taleedSheet(isPresented: Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })) {
                if let sheet { sheetContent(sheet) }
            }
            .taleedConfirmation(isPresented: accepting != nil) {
                ConfirmationModalCard(
                    title: l10n.format(.appOfferAcceptTitle, PriceFormatter.format(accepting?.amount ?? 0, language: l10n.language)),
                    message: l10n.string(accepting?.sentBy == .seller ? .appOfferAcceptBodyBuyer : .appOfferAcceptBodySeller),
                    confirmTitle: l10n.string(.offersAccept),
                    onConfirm: accept,
                    onCancel: { accepting = nil },
                    icon: .checkCircle,
                    tone: .positive
                )
            }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ConversationOfferSheet) -> some View {
        switch sheet {
        case let .make(entry, range, price):
            OfferAmountSheet(
                title: l10n.string(entry.titleKey),
                hint: price.map { l10n.format(.offersOfferHint, PriceFormatter.format($0, language: l10n.language)) },
                range: range,
                submit: { amount in close(after: await model.makeOffer(amount: amount)) },
                onClose: { self.sheet = nil }
            )
        case let .counter(offer):
            if let range = offer.counterRange {
                OfferAmountSheet(
                    title: l10n.string(.offersCounter),
                    hint: l10n.format(.offersTheyOffered, (counterpartName ?? l10n.string(.chatDeletedUser)).isolatedLeftToRight,
                                      PriceFormatter.format(offer.amount, language: l10n.language)),
                    range: range,
                    initialAmount: OfferAmounts.counterSuggestion(for: offer),
                    submit: { amount in close(after: await model.counter(offer, amount: amount)) },
                    onClose: { self.sheet = nil }
                )
            }
        }
    }

    private func close(after step: OfferSheetStep) -> OfferSheetStep {
        if step == .finish { sheet = nil }
        return step
    }

    private func accept() {
        guard let offer = accepting else { return }
        accepting = nil
        Task {
            // The buyer accepted the seller's price: checkout at once (§7 G10).
            if let checkout = await model.respond(.accept, to: offer) { router.pushSignedIn(.checkout(checkout)) }
        }
    }
}
