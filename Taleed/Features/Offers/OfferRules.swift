import Foundation

// Which offer buttons the conversation shows, and the amounts its sheets start from (screens.md §2 G10,
// §7 G9 and G10, slice C "Offers"). Every permission comes from the server's flags; pure, so the tests
// check them.

/// The offer pinned under the item strip of a conversation, and its buttons.
struct PinnedOffer: Equatable {
    let offer: ChatOffer
    /// "Accepter", with a confirmation (`canAccept`).
    let canAccept: Bool
    /// "Refuser" (`canDecline`).
    let canDecline: Bool
    /// "Contre-offre": a sheet bounded by `counterRange` (`canCounter`).
    let canCounter: Bool
    /// "Annuler l'offre" (`canCancel`).
    let canWithdraw: Bool
    /// "Payer maintenant · X" (`canPay`): checkout at the offer's price.
    let payment: CheckoutTarget?

    /// The offer to pin: the one waiting for an answer, or else the accepted offer the buyer can still
    /// pay (`payableOffer`, API 1.5.7, however old its messages). `current` gives an offer as it stands
    /// now (`ChatOfferStates`): a message received after the load may say it was paid meanwhile. A
    /// pending offer past `expiresAt` is no longer pinned (slice C).
    static func find(conversation: ConversationDetail?, current: (ChatOffer) -> ChatOffer, now: Date) -> PinnedOffer? {
        guard let conversation, !conversation.isOfficial else { return nil }
        if let pending = conversation.pendingOffer.map(current), pending.displayStatus(at: now) == .pending {
            return PinnedOffer(offer: pending, now: now)
        }
        if let payable = conversation.payableOffer.map(current), payable.status == .accepted, payable.canPay {
            return PinnedOffer(offer: payable, now: now)
        }
        return nil
    }

    init(offer: ChatOffer, now: Date) {
        self.offer = offer
        let waits = offer.displayStatus(at: now) == .pending
        canAccept = waits && offer.canAccept
        canDecline = waits && offer.canDecline
        canCounter = waits && offer.canCounter && offer.counterRange != nil
        canWithdraw = waits && offer.canCancel
        // A bundle offer is paid through the bundle's checkout (the website's `?bundle=…&offer=…`).
        payment = offer.canPay
            ? CheckoutTarget(listingId: offer.listingId, offerId: offer.id, bundleId: offer.bundle?.id)
            : nil
    }

    /// Nothing to tap: the card still shows the offer and its status.
    var hasActions: Bool { canAccept || canDecline || canCounter || canWithdraw || payment != nil }
}

/// The offer button next to the composer: "Faire une offre" for the buyer, "Proposer un prix" for the
/// seller (§7 G10: the apps follow the API, which lets both offer in the conversation).
enum ConversationOfferEntry: Equatable {
    case makeOffer
    case proposePrice

    /// Shown while the server gives `offerRange`, the conversation takes replies and no offer waits.
    static func entry(for conversation: ConversationDetail?, pinned: PinnedOffer?, now: Date) -> ConversationOfferEntry? {
        guard let conversation, conversation.canReply, !conversation.isOfficial, conversation.offerRange != nil else {
            return nil
        }
        if let pinned, pinned.offer.displayStatus(at: now) == .pending { return nil }
        switch conversation.role {
        case .buyer: return .makeOffer
        case .seller: return .proposePrice
        case .unknown: return nil
        }
    }
}

enum OfferAmounts {
    /// The counter-offer the sheet starts from when the seller answers a buyer's offer: halfway between
    /// the offer and the top of `counterRange` (the website's placeholder, §7 G9 "prefilled with the
    /// midpoint"), kept inside the bounds. Nil when the buyer answers a price the seller proposed: that
    /// midpoint is above the seller's own price, so the field starts empty, as on the website.
    static func counterSuggestion(for offer: ChatOffer) -> Int? {
        guard offer.sentBy == .buyer, let range = offer.counterRange else { return nil }
        let middle = Int((Double(offer.amount + range.max) / 2).rounded())
        return min(max(middle, range.min), range.max)
    }
}

/// What an offer sheet does after its amount was sent.
enum OfferSheetStep: Equatable {
    /// Done (or failed with a toast): close the sheet.
    case finish
    /// `offer_out_of_range`: the bounds again, in red; the sheet stays.
    case showRange(AmountRange)
    /// Nothing happened (already sending): the sheet stays as it is.
    case stay
}

extension ApiError {
    /// Offer and bundle errors after which the screen reloads its state (slice C, Offers and Bundles):
    /// the offer moved on, the item sold, the members' relation changed, or the thing is gone.
    var reloadsOfferState: Bool {
        switch code {
        case .offerOutOfRange, .offerPending, .offerClosed, .listingUnavailable, .blocked, .conversationReadOnly, .forbidden,
             .notFound:
            true
        default:
            false
        }
    }
}
