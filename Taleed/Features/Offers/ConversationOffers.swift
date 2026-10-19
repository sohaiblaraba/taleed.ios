import Foundation

/// The offer action running, for its button's spinner. One at a time.
enum ConversationOfferWork: Equatable {
    case make
    case respond(OfferResponse, offerId: String)
    case counter(offerId: String)
}

/// The offer actions of the conversation screen (screens.md §2 G10, slice C "Offers"): an offer or a
/// proposed price, accept, decline, counter and withdraw. Each one runs once per tap, never repeated on
/// its own; its answer joins the conversation at once, then the conversation reloads for `pendingOffer`
/// and `offerRange`. Errors show as a toast and reload the conversation when they say it changed.
extension ConversationViewModel {
    /// The offer pinned under the item strip and its buttons: the one waiting for an answer, or the
    /// accepted one the buyer can pay.
    var pinnedOffer: PinnedOffer? {
        PinnedOffer.find(conversation: conversation, messages: messages, current: offers.current, now: currentDate)
    }

    /// "Faire une offre" or "Proposer un prix" next to the composer.
    var offerEntry: ConversationOfferEntry? {
        ConversationOfferEntry.entry(for: conversation, pinned: pinnedOffer, now: currentDate)
    }

    /// An offer action's answer (slice C, Offers): its messages join the conversation at once (the stream
    /// may bring them again; merged by id), and the offer as it stands now updates every card.
    func applyOfferResult(_ result: OfferActionResult) {
        merge(result.messages)
        offers.record(offer: result.offer)
    }

    /// "Envoyer l'offre" in the "Faire une offre" / "Proposer un prix" sheet.
    func makeOffer(amount: Int) async -> OfferSheetStep {
        guard let offerApi, offerWork == nil else { return .stay }
        offerWork = .make
        defer { offerWork = nil }
        do {
            let result = try await offerApi.makeConversationOffer(conversationId: conversationId, amount: amount)
            applyOfferResult(result)
            notice = .confirmation(.offersOfferSent)
            onSent?()
            await reloadConversation(automatic: false)
            return .finish
        } catch {
            return await sheetFailure(error) { $0.conversation?.offerRange }
        }
    }

    /// "Contre-offre" in its sheet: the counter-offer replaces the offer (`COUNTERED`) and waits for the
    /// other member's answer.
    func counter(_ offer: ChatOffer, amount: Int) async -> OfferSheetStep {
        guard let offerApi, offerWork == nil else { return .stay }
        offerWork = .counter(offerId: offer.id)
        defer { offerWork = nil }
        do {
            applyOfferResult(try await offerApi.counter(offerId: offer.id, amount: amount))
            await reloadConversation(automatic: false)
            return .finish
        } catch {
            return await sheetFailure(error) { model in
                // The same offer, if it still waits: its bounds may have moved with the price.
                model.pinnedOffer.flatMap { $0.offer.id == offer.id && $0.canCounter ? $0.offer.counterRange : nil }
            }
        }
    }

    /// "Accepter" (after the confirmation), "Refuser" or "Annuler l'offre". When the buyer accepts the
    /// seller's price, the answer allows paying at once: checkout opens (§7 G10, as on the website).
    /// - Returns: the checkout to open, if any.
    func respond(_ response: OfferResponse, to offer: ChatOffer) async -> CheckoutTarget? {
        guard let offerApi, offerWork == nil else { return nil }
        offerWork = .respond(response, offerId: offer.id)
        defer { offerWork = nil }
        do {
            let result = try await offerApi.respond(response, offerId: offer.id)
            applyOfferResult(result)
            await reloadConversation(automatic: false)
            guard response == .accept, result.offer.canPay else { return nil }
            return PinnedOffer(offer: result.offer, now: currentDate).payment
        } catch {
            notice = .error(error)
            if error.reloadsOfferState { await reloadConversation(automatic: false) }
            return nil
        }
    }

    /// `offer_out_of_range` keeps the sheet open with the bounds after a reload (the price may have
    /// changed); any other error closes it with a toast, reloading when the error says the state changed.
    private func sheetFailure(_ error: ApiError, range: (ConversationViewModel) -> AmountRange?) async -> OfferSheetStep {
        if error.reloadsOfferState { await reloadConversation(automatic: false) }
        if error.code == .offerOutOfRange, let fresh = range(self) { return .showRange(fresh) }
        if error.code == .offerPending {
            // An offer already waits in this conversation: it is now pinned.
            notice = .information(.offersErrorActive)
        } else {
            notice = .error(error)
        }
        return .finish
    }
}
