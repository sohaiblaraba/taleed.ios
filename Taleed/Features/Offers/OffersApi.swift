import Foundation
import TaleedAPI

/// What an offer action answered (`OfferActionResult`, slice C "Offers"): the conversation it happened in,
/// the offer it made or answered as it stands now, and the messages it posted, oldest first.
struct OfferActionResult: Equatable, Sendable {
    let conversationId: String
    let offer: ChatOffer
    let messages: [ChatMessage]
}

/// An answer to an offer the other member made, or the member's own offer withdrawn.
enum OfferResponse: Equatable, Sendable {
    /// `POST /offers/{id}/accept` (`canAccept`).
    case accept
    /// `POST /offers/{id}/decline` (`canDecline`).
    case decline
    /// `POST /offers/{id}/cancel` (`canCancel`): "Annuler l'offre".
    case withdraw
}

/// The offer calls of the conversation screen (screens.md §2 G10, slice C "Offers"). An offer from the
/// listing screen goes through `ListingDetailApi.makeOffer`, a bundle offer through `BundlesApi`.
///
/// None is ever repeated on its own (slice C, Retrying): a repeat after a lost answer says
/// `offer_pending` or `offer_closed`, and the screen reloads the conversation.
@MainActor
protocol OffersApi: AnyObject {
    /// `POST /conversations/{id}/offers {amount}`: the buyer's offer, or the price the seller proposes.
    func makeConversationOffer(conversationId: String, amount: Int) async throws(ApiError) -> OfferActionResult
    /// Accept, decline or withdraw.
    func respond(_ response: OfferResponse, offerId: String) async throws(ApiError) -> OfferActionResult
    /// `POST /offers/{id}/counter {amount}`: `offer` is the counter-offer, `PENDING`.
    func counter(offerId: String, amount: Int) async throws(ApiError) -> OfferActionResult
}

extension GeneratedTaleedApi: OffersApi {
    func makeConversationOffer(conversationId: String, amount: Int) async throws(ApiError) -> OfferActionResult {
        let body = OfferAmount(amount: amount)
        let result = try await caller.call(.write) {
            try await OffersAPI.makeConversationOffer(id: conversationId, offerAmount: body, apiConfiguration: $0)
        }
        return OfferActionResult(result)
    }

    func respond(_ response: OfferResponse, offerId: String) async throws(ApiError) -> OfferActionResult {
        let result = try await caller.call(.write) { configuration in
            switch response {
            case .accept: try await OffersAPI.acceptOffer(id: offerId, apiConfiguration: configuration)
            case .decline: try await OffersAPI.declineOffer(id: offerId, apiConfiguration: configuration)
            case .withdraw: try await OffersAPI.cancelOffer(id: offerId, apiConfiguration: configuration)
            }
        }
        return OfferActionResult(result)
    }

    func counter(offerId: String, amount: Int) async throws(ApiError) -> OfferActionResult {
        let body = OfferAmount(amount: amount)
        let result = try await caller.call(.write) {
            try await OffersAPI.counterOffer(id: offerId, offerAmount: body, apiConfiguration: $0)
        }
        return OfferActionResult(result)
    }
}

extension OfferActionResult {
    init(_ result: TaleedAPI.OfferActionResult) {
        self.init(conversationId: result.conversationId, offer: ChatOffer(result.offer),
                  messages: result.messages.map(ChatMessage.init))
    }
}
