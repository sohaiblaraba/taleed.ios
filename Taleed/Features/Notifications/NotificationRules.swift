import Foundation
import Observation

/// One row of the notifications screen (`GET /notifications`). `text` is the server's sentence in the
/// response language, shown as given (never in the string files).
struct NotificationRow: Identifiable, Equatable, Sendable {
    let id: String
    /// `ORDER_SHIPPED`, `NEW_OFFER`…; new types appear without notice.
    let type: String
    let text: String
    /// The website page it is about, routed like an app link. Nil: nothing to open.
    let url: URL?
    let isRead: Bool
    let createdAt: Date

    var theme: NotificationTheme { NotificationTheme(type: type) }

    /// Where a tap leads: nil for a row without a link, and for one that points at the notifications
    /// screen itself (`REPORT_RESOLVED`, `REPORT_DISMISSED`: the screen is already open, §7 G15). Such a
    /// row is drawn plain, like the website's rows without a link.
    var destination: AppDestination? {
        guard let url else { return nil }
        let destination = LinkRouter.destination(for: url)
        return destination == .screen(.notifications) ? nil : destination
    }
}

/// The icon family of a notification type (screens.md §2 G15, slice E "Notifications"). An unknown
/// type gets the generic bell.
enum NotificationTheme: Equatable, Sendable {
    case offers, orders, disputes, money, community, account, boosts, other

    init(type: String) {
        let type = type.uppercased()
        switch type {
        case "NEW_OFFER": self = .offers
        case "TOPUP_PAID", "REFERRAL_REWARD", "VERIFICATION_VOUCHER": self = .money
        case "NEW_FAVORITE", "NEW_FOLLOWER", "FOLLOWED_MEMBER_LISTED", "REVIEW_RECEIVED", "REFERRAL_SIGNUP": self = .community
        case "VERIFICATION_APPROVED", "VERIFICATION_REJECTED", "REPORT_RESOLVED", "REPORT_DISMISSED": self = .account
        default:
            if type.hasPrefix("OFFER_") {
                self = .offers
            } else if type.hasPrefix("ORDER_") {
                self = .orders
            } else if type.hasPrefix("DISPUTE_") {
                self = .disputes
            } else if type.hasPrefix("PAYOUT_") {
                self = .money
            } else if type.hasPrefix("BOOST_") {
                self = .boosts
            } else {
                self = .other
            }
        }
    }

    var icon: TaleedIcon {
        switch self {
        case .offers: .chatCircleDots
        case .orders: .truck
        case .disputes: .warningCircle
        case .money: .money
        case .community: .user
        case .account: .shieldCheck
        case .boosts: .sparkle
        case .other: .bell
        }
    }
}

/// Tells an open notifications screen to load its first page again and mark it read: a push that
/// arrives while the app is open (slice E: "When a push arrives while the screen is open, do the
/// same"), or a link to `/notifications` (a push without a link of its own carries that one).
@MainActor
@Observable
final class NotificationsFeed {
    /// Bumped by every arrival; the screen reloads when it changes.
    private(set) var sequence = 0

    func somethingArrived() {
        sequence += 1
    }
}
