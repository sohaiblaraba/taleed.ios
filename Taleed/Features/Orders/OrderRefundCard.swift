import SwiftUI

/// The refund the Taleed team owes the buyer (slice H; the website's refund notice): "Refund · 5 200 DA",
/// "To your card — Being sent", then how it travels, or once sent "Sent on {date} · Reference: {ref}";
/// for a bank refund without payout details, the sentence asking for them and "Add payout details",
/// which opens Earnings with the payout details sheet.
struct OrderRefundCard: View {
    let block: OrderRules.RefundBlock
    let onAddPayoutDetails: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        InlineAlert(kind: block.isSent ? .success : .info,
                    title: "\(l10n.string(.ordersRefundTitle)) · \(PriceFormatter.format(block.amount, language: l10n.language))",
                    message: details,
                    actionTitle: block.asksPayoutDetails ? l10n.string(.ordersRefundAddPayoutDetails) : nil,
                    action: block.asksPayoutDetails ? onAddPayoutDetails : nil)
            .accessibilityIdentifier("order.refund")
    }

    private var details: String {
        var lines = [block.summary]
        if block.isSent {
            let sent = [
                block.sentAt.map { l10n.format(.ordersRefundSentOn, OrderText.date($0, locale: l10n.language.formattingLocale)) },
                block.reference.map { l10n.format(.ordersRefundReference, $0.isolatedLeftToRight) },
            ].compactMap { $0 }
            if !sent.isEmpty { lines.append(sent.joined(separator: WalletText.separator)) }
        } else {
            switch block.hint {
            case .card: lines.append(l10n.string(.ordersRefundCardHint))
            case .bank: lines.append(l10n.string(.ordersRefundBankHint))
            case nil: break
            }
        }
        if block.asksPayoutDetails { lines.append(l10n.string(.ordersRefundNeedsPayoutAccount)) }
        return lines.joined(separator: "\n")
    }
}
