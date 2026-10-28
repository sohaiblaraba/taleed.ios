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

    /// Where a tap leads: nil for a row without a link, for one that points at the notifications
    /// screen itself (`REPORT_RESOLVED`, `REPORT_DISMISSED`: the screen is already open, §7 G15), and
    /// for a staff role offer (`ROLE_OFFERED`, `/role-offers`: staff roles are web-only, decision 8).
    /// Such a row is drawn plain, like the website's rows without a link.
    var destination: AppDestination? {
        // The decisions link to `/settings`; the app opens the verification section itself (§7 G17).
        if Self.verificationDecisions.contains(type.uppercased()) { return .screen(.identityVerification) }
        guard let url, !isRoleOffer(url) else { return nil }
        let destination = LinkRouter.destination(for: url)
        return destination == .screen(.notifications) ? nil : destination
    }

    private static let verificationDecisions: Set<String> = ["VERIFICATION_APPROVED", "VERIFICATION_REJECTED"]

    /// A `ROLE_OFFERED` row, or any row whose link is the website's `/role-offers` page (with or
    /// without a language prefix).
    private func isRoleOffer(_ url: URL) -> Bool {
        if type.uppercased() == "ROLE_OFFERED" { return true }
        var segments = url.pathComponents.filter { $0 != "/" }
        if let first = segments.first, ["ar", "en", "fr"].contains(first.lowercased()) {
            segments.removeFirst()
        }
        return segments.first?.lowercased() == "role-offers"
    }
}

/// The icon family of a notification type (screens.md §2 G15, slice E "Notifications"). An unknown
/// type gets the generic bell.
enum NotificationTheme: Equatable, Sendable {
    /// `accountIssue`: a refusal about the account (a verification rejected, a report dismissed), drawn
    /// with a warning shield rather than the check of an approval.
    case offers, orders, disputes, money, community, account, accountIssue, boosts, other

    init(type: String) {
        let type = type.uppercased()
        if let theme = Self.byType[type] {
            self = theme
        } else {
            self = Self.byPrefix.first { type.hasPrefix($0.prefix) }?.theme ?? .other
        }
    }

    private static let byType: [String: NotificationTheme] = [
        "NEW_OFFER": .offers,
        "TOPUP_PAID": .money, "REFERRAL_REWARD": .money, "VERIFICATION_VOUCHER": .money,
        // Slice H: a refund sent to the buyer, a late card payment to refund (admins). `PAYOUT_CREATED` and
        // `PAYOUT_DETAILS_MISSING` take the `PAYOUT_` prefix.
        "REFUND_SENT": .money, "REFUND_LATE_PAYMENT": .money,
        "NEW_FAVORITE": .community, "NEW_FOLLOWER": .community, "FOLLOWED_MEMBER_LISTED": .community,
        "REVIEW_RECEIVED": .community, "REFERRAL_SIGNUP": .community,
        "VERIFICATION_APPROVED": .account, "REPORT_RESOLVED": .account,
        "VERIFICATION_REJECTED": .accountIssue, "REPORT_DISMISSED": .accountIssue,
    ]

    private static let byPrefix: [(prefix: String, theme: NotificationTheme)] = [
        ("OFFER_", .offers), ("ORDER_", .orders), ("DISPUTE_", .disputes), ("PAYOUT_", .money), ("BOOST_", .boosts),
    ]

    var icon: TaleedIcon {
        switch self {
        case .offers: .chatCircleDots
        case .orders: .truck
        case .disputes: .warningCircle
        case .money: .money
        case .community: .user
        case .account: .shieldCheck
        case .accountIssue: .shieldWarning
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
