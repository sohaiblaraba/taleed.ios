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

    /// The offer card's eyebrow: "Offre sur un lot · 2 articles", "Votre offre" (the member's own),
    /// "Offre" (the buyer's, seen by the seller) or "Offre du vendeur" (§7 G9).
    enum OfferEyebrow: Equatable {
        case bundle(count: Int)
        case mine
        case buyer
        case seller
    }

    static func offerEyebrow(_ offer: ChatOffer) -> OfferEyebrow {
        if let bundle = offer.bundle { return .bundle(count: bundle.items.count) }
        if offer.isMine { return .mine }
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

    /// The time under a bubble ("14:05", "2:05 PM"): the app's time format (`OrderText.time`).
    static func time(_ date: Date, locale: Locale) -> String {
        OrderText.time(date, locale: locale)
    }

    /// The inbox's short time of the last message, so the item's title keeps its room: "34 s", "5 min",
    /// "7 h" within a day, "hier", "3 j" within a week, then the date ("12 oct.", with the year when it is
    /// not this one). VoiceOver reads the full relative time instead.
    static func inboxTime(_ date: Date, now: Date = Date(), locale: Locale, calendar: Calendar = .current) -> String {
        var calendar = calendar
        calendar.locale = locale
        let seconds = max(0, now.timeIntervalSince(date))
        let units = DateComponentsFormatter()
        units.calendar = calendar
        units.unitsStyle = .short
        units.maximumUnitCount = 1
        if seconds < 86400 {
            units.allowedUnits = seconds < 60 ? [.second] : seconds < 3600 ? [.minute] : [.hour]
            return units.string(from: seconds) ?? ""
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 1 {
            let relative = RelativeDateTimeFormatter()
            relative.locale = locale
            relative.dateTimeStyle = .named
            return relative.localizedString(from: DateComponents(day: -1))
        }
        if days < 7 {
            units.allowedUnits = [.day]
            return units.string(from: TimeInterval(days * 86400)) ?? ""
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        guard sameYear else { return OrderText.date(date, locale: locale) }
        // The app's date without its year: "12 oct.", "12 Oct", "12‏/10".
        let language = AppLanguage(locale: locale)
        let formatter = DateFormatter()
        formatter.locale = OrderText.webLocale(language)
        formatter.calendar = calendar
        formatter.dateFormat = language == .ar ? "dd\u{200F}/MM" : "d\u{00A0}MMM"
        return formatter.string(from: date)
    }

    /// The day above a day's messages: "Aujourd'hui", "Hier", then the app's date "12 oct. 2026" (the
    /// system's relative names, nothing to translate; the website's locales give the app's medium date).
    static func day(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = OrderText.webLocale(AppLanguage(locale: locale))
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        // A standalone label: "Aujourd’hui", not "aujourd’hui" (Android capitalises it too).
        formatter.formattingContext = .beginningOfSentence
        return formatter.string(from: date)
    }
}
