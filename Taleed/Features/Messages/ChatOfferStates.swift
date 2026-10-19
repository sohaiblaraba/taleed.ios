import Foundation

/// The latest state of each offer of a conversation. The server sends each message's offer, and the
/// conversation's `pendingOffer` and `payableOffer`, as they stand when it answers: the latest answer
/// wins, in the order the app received them, never by comparing the phone's clock with the server's.
struct ChatOfferStates {
    /// From the messages: the offer and the answer it came in.
    private var fromMessages: [String: (offer: ChatOffer, answer: Int)] = [:]
    /// The conversation's `pendingOffer` and `payableOffer` from its latest load. A load that no longer
    /// lists one drops it, and a message received after that load wins over it.
    private var fromConversation: [String: (offer: ChatOffer, answer: Int)] = [:]
    /// Counts the answers, in the order they arrived.
    private var answers = 0

    mutating func record(_ messages: [ChatMessage]) {
        answers += 1
        for offer in messages.compactMap(\.offer) {
            fromMessages[offer.id] = (offer, answers)
        }
    }

    /// An offer as an action answered it (G10): newer than every copy received before.
    mutating func record(offer: ChatOffer) {
        answers += 1
        fromMessages[offer.id] = (offer, answers)
    }

    /// The offers of a conversation load (`pendingOffer`, `payableOffer`).
    mutating func record(conversationOffers: [ChatOffer]) {
        answers += 1
        fromConversation = Dictionary(conversationOffers.map { ($0.id, ($0, answers)) }, uniquingKeysWith: { _, new in new })
    }

    /// The offer as it stands now, from the card's own copy.
    func current(_ offer: ChatOffer) -> ChatOffer {
        let seen = fromMessages[offer.id]
        if let loaded = fromConversation[offer.id], loaded.answer > seen?.answer ?? 0 { return loaded.offer }
        return seen?.offer ?? offer
    }
}
