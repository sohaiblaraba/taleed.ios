import Foundation

/// What the listing screen offers, from the server's flags only (screens.md §2 G4 "Buttons by state",
/// §0.4, slice B "What the seller can do"). Signed out, the API still answers `canBuy`, `offerRange`
/// and `canMessage`: the buttons show and ask to sign in (§0.5).
struct ListingDetailActions: Equatable {
    /// The notice instead of the buy buttons.
    enum Banner: Equatable {
        case reserved, sold
        /// Only the seller sees a hidden listing.
        case hidden
    }

    /// "Acheter", or "Payer maintenant · {amount}" with the accepted offer (screens.md §7 G4).
    enum BuyButton: Equatable {
        case buy
        case payNow(offerId: String, amount: Int)

        var offerId: String? {
            if case let .payNow(offerId, _) = self { return offerId }
            return nil
        }
    }

    /// Hide or resume, by status.
    enum Visibility: Equatable { case hide, resume }

    /// The seller's actions (slice B table): Edit, Hide or Resume, Delete.
    struct OwnerActions: Equatable {
        var canEdit = false
        var visibility: Visibility?
        var canDelete = false

        init(status: ListingStatus) {
            switch status {
            case .active:
                self.init(canEdit: true, visibility: .hide, canDelete: true)
            case .hidden:
                self.init(canEdit: true, visibility: .resume, canDelete: true)
            case .sold:
                // Once its order is over: the server answers `listing_locked` before that.
                self.init(canEdit: false, visibility: nil, canDelete: true)
            case .reserved, .draft, .unknown:
                self.init(canEdit: false, visibility: nil, canDelete: false)
            }
        }

        init(canEdit: Bool, visibility: Visibility?, canDelete: Bool) {
            self.canEdit = canEdit
            self.visibility = visibility
            self.canDelete = canDelete
        }
    }

    /// The bundle toggle while the member builds a bundle with this seller (slice F).
    enum BundleToggle: Equatable { case add, remove }

    var owner: OwnerActions?
    var banner: Banner?
    var showsViewOrder = false
    var buy: BuyButton?
    var showsMakeOffer = false
    var showsMessage = false
    var showsShopBundles = false
    var showsReport = false
    var bundleToggle: BundleToggle?
    /// The amount of the offer the seller accepted, for the buyer's notice.
    var acceptedOfferAmount: Int?

    init(listing: ListingDetail, isSignedIn: Bool) {
        banner = switch listing.status {
        case .reserved: .reserved
        case .sold: .sold
        case .hidden: .hidden
        case .active, .draft, .unknown: nil
        }
        showsViewOrder = listing.orderId != nil
        if listing.isOwner {
            // No buy, offer, message, report or boost on the member's own listing.
            owner = OwnerActions(status: listing.status)
            return
        }
        let isOnSale = listing.status == .active
        if isOnSale, listing.canBuy {
            buy = listing.acceptedOffer.map { .payNow(offerId: $0.id, amount: $0.amount) } ?? .buy
        }
        showsMakeOffer = isOnSale && listing.offerRange != nil
        showsMessage = listing.canMessage
        showsShopBundles = listing.canBundle
        showsReport = true
        acceptedOfferAmount = isOnSale ? listing.acceptedOffer?.amount : nil
        if isSignedIn, isOnSale, listing.openBundleId != nil, listing.seller.username != nil {
            bundleToggle = listing.inMyBundle ? .remove : .add
        }
    }

    /// Whether the sticky bar under the content has anything to show.
    var hasBottomBar: Bool { buy != nil || showsMakeOffer || showsViewOrder }
}

/// The amount typed in the offer sheet, checked against `offerRange` before sending (screens.md §2 G10:
/// the server's bounds; the API still decides with `offer_out_of_range`).
enum OfferAmountInput: Equatable {
    case empty
    case outOfRange
    case valid(Int)

    /// Western, Arabic-Indic and Persian digits are read alike; spaces and separators are ignored.
    init(text: String, range: AmountRange) {
        let digits = Self.normalizedDigits(text)
        guard !digits.isEmpty else {
            self = .empty
            return
        }
        guard let amount = Int(digits), range.contains(amount) else {
            self = .outOfRange
            return
        }
        self = .valid(amount)
    }

    /// The typed text with only its digits, in Western form. Six digits at most would already be over
    /// any price, so the field keeps nine.
    static func normalizedDigits(_ text: String) -> String {
        String(text.compactMap { character -> Character? in
            guard let value = character.wholeNumberValue, (0...9).contains(value), character.isNumber else { return nil }
            return Character(String(value))
        }.prefix(9))
    }
}

/// "En ligne" or "Vu il y a 3 heures" (screens.md §7 G4, the website's `formatRelative`): seconds under a
/// minute, then minutes, hours, days, and months from 30 days, with "numeric: auto" wording.
enum RelativeTimeText {
    static func string(for date: Date, now: Date = Date(), locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let seconds = Int((date.timeIntervalSince(now)).rounded())
        let magnitude = abs(seconds)
        let components: DateComponents = switch magnitude {
        case ..<60: DateComponents(second: seconds)
        case ..<3600: DateComponents(minute: Int((Double(seconds) / 60).rounded()))
        case ..<86400: DateComponents(hour: Int((Double(seconds) / 3600).rounded()))
        case ..<2_592_000: DateComponents(day: Int((Double(seconds) / 86400).rounded()))
        default: DateComponents(month: Int((Double(seconds) / 2_592_000).rounded()))
        }
        return formatter.localizedString(from: components)
    }
}

/// The seller's average, "4.8": one decimal in Latin digits, as the website's stars print it
/// (`toFixed(1)`) in every language.
enum RatingText {
    static func average(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

extension AppLanguage {
    /// The locale of dates and relative times: Arabic as Algeria writes it, with Latin digits (as
    /// the prices, decision D-5).
    var formattingLocale: Locale {
        switch self {
        case .ar: Locale(identifier: "ar_DZ@numbers=latn")
        case .fr, .en: locale
        }
    }
}
