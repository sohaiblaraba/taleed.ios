import Foundation

/// The copy and formats of the inbox and the conversation (screens.md §7 G9): which website key says
/// what, the unread pill, the dates. Pure, so the tests check them.
enum ChatText {
    /// The inbox badge of a listing that is no longer for sale: "Réservé", "Vendu", or "Indisponible"
    /// for a hidden, removed or unknown one (slice C: "no longer available"). Nil while for sale.
    static func listingStatusKey(_ status: ChatListingStatus) -> L10nKey? {
        switch status {
        case .active: nil
        case .reserved: .listingStatusReserved
        case .sold: .listingStatusSold
        case .hidden, .removed, .unknown: .bundleUnavailable
        }
    }

    /// The badge's tone: reserved is a warning, the others neutral.
    static func listingStatusTone(_ status: ChatListingStatus) -> TaleedTone {
        status == .reserved ? .warning : .neutral
    }

    /// The offer card's status ("En attente", "Acceptée"…); an unknown one is "closed" (slice C).
    static func offerStatusKey(_ status: ChatOfferStatus) -> L10nKey {
        switch status {
        case .pending: .offersStatusPending
        case .accepted: .offersStatusAccepted
        case .declined: .offersStatusDeclined
        case .countered: .offersStatusCountered
        case .cancelled: .offersStatusCancelled
        case .expired: .offersStatusExpired
        case .unknown: .appOfferStatusClosed
        }
    }

    static func offerStatusTone(_ status: ChatOfferStatus) -> TaleedTone {
        switch status {
        case .accepted: .success
        case .pending: .brand
        case .declined, .countered, .cancelled, .expired, .unknown: .neutral
        }
    }

    /// The offer card's eyebrow: "Offre sur un lot · 2 articles", "Faire une offre" (a buyer's offer) or
    /// "Offre du vendeur" (§7 G9).
    enum OfferEyebrow: Equatable {
        case bundle(count: Int)
        case buyer
        case seller
    }

    static func offerEyebrow(_ offer: ChatOffer) -> OfferEyebrow {
        if let bundle = offer.bundle { return .bundle(count: bundle.items.count) }
        return offer.sentBy == .seller ? .seller : .buyer
    }

    /// The text in place of the composer when `canReply` is false (slice C, The conversation screen).
    enum ReadOnlyNotice: Equatable {
        /// "Message officiel de Taleed — les réponses sont désactivées."
        case official
        /// "Vous avez bloqué @x." with "Débloquer".
        case youBlocked(handle: String)
        /// The neutral text for the member who was blocked: "Vous ne pouvez plus écrire à ce membre."
        case blocked
        /// "Ce membre a supprimé son compte — les réponses sont désactivées."
        case memberDeleted
        /// A reason added after this build.
        case generic
    }

    static func readOnlyNotice(for conversation: ConversationDetail) -> ReadOnlyNotice? {
        guard !conversation.canReply else { return nil }
        switch conversation.replyBlock {
        case .official: return .official
        case .blocked:
            // Only the member who blocked hears about it; the other side reads the neutral text.
            if conversation.isBlocked, let handle = conversation.counterpart?.displayName { return .youBlocked(handle: handle) }
            return .blocked
        case .memberDeleted: return .memberDeleted
        case .unknown, nil:
            return conversation.isOfficial ? .official : .generic
        }
    }

    /// "Écrivez un message…" takes 2 000 characters after trimming (`MessageCreate.textRule`); the API
    /// counts them as the website does (UTF-16), so a longer text is cut there.
    static let maxTextLength = 2000

    static func limited(_ text: String) -> String {
        guard text.utf16.count > maxTextLength else { return text }
        var result = ""
        var count = 0
        for character in text {
            let length = character.utf16.count
            guard count + length <= maxTextLength else { break }
            result.append(character)
            count += length
        }
        return result
    }

    /// The trimmed text to send, nil when only spaces remain.
    static func sendableText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : limited(trimmed)
    }

    // MARK: Dates

    /// The time under a bubble ("14:05"), as the website's `timeStyle: short`.
    static func time(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// The day above a day's messages: "Aujourd'hui", "Hier", then "12 oct. 2026" (the system's
    /// relative names, nothing to translate).
    static func day(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}
