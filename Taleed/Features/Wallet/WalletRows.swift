import SwiftUI

/// The "Historique" tab: its states, then the lines in one bordered card, as the website's list.
struct WalletHistorySection: View {
    let list: PagedList<WalletEntryRow>
    /// The labels of the top-up lines' methods.
    var topUpMethods: [PaymentChoice] = []
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router

    var body: some View {
        WalletListSection(list: list, emptyIcon: .money) { entry in
            WalletEntryRowView(entry: entry, topUpMethods: topUpMethods,
                               onOpenOrder: entry.orderId.map { id in { router.push(.order(id: id)) } })
        }
    }
}

/// The "Virements" tab.
struct WalletPayoutsSection: View {
    let list: PagedList<PayoutRow>
    @Environment(AppRouter.self) private var router

    var body: some View {
        WalletListSection(list: list, emptyIcon: .money) { payout in
            PayoutRowView(payout: payout, onOpenProof: payout.proofURL.map { url in { router.openInBrowser(url) } })
        }
    }
}

/// A tab's list: a spinner while the first page loads, the error with Retry, the design-system empty
/// state ("Aucune opération pour le moment." under the tab's icon, as the notifications') when empty,
/// otherwise the rows with dividers, then the pagination footer as a sibling in the screen's lazy stack.
private struct WalletListSection<Item: Identifiable & Sendable, Row: View>: View where Item.ID: Sendable {
    let list: PagedList<Item>
    let emptyIcon: TaleedIcon
    @ViewBuilder let row: (Item) -> Row
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s12) {
            if list.hasLoaded {
                if list.items.isEmpty {
                    EmptyState(title: l10n.string(.walletNoEntries), icon: emptyIcon)
                        .padding(.top, TaleedSpacing.s8)
                        .accessibilityIdentifier("wallet.empty")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
                            }
                            row(item)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                    .taleedCard()
                    .padding(.horizontal, TaleedLayout.screenMargin)
                }
            } else if let error = list.error {
                SectionErrorView(error: error) { Task { await list.reload() } }
            } else {
                ProgressView()
                    .tint(TaleedColor.brandPrimary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityLabel(l10n.string(.commonLoading))
            }
        }
        .padding(.vertical, TaleedSpacing.s16)
        .task { await list.loadIfNeeded() }
        // A child of its own in the screen's lazy stack, not inside the block above: it appears, and asks
        // for the next page, only once the member scrolls to the end of the rows.
        if list.hasLoaded, !list.items.isEmpty {
            PaginationFooter(list: list)
        }
    }
}

/// A history line: the type's icon, the server's label, "T-000104 · 4 oct. 2026" (vouchers: their status,
/// the date and "Expire le …" while active), and the signed amount. A line about an order opens it (a
/// chevron); the others keep the chevron's place, so every amount ends on the same line. At accessibility
/// sizes the line stacks (icon, label, detail, then the amount), so the label keeps the width.
struct WalletEntryRowView: View {
    let entry: WalletEntryRow
    var topUpMethods: [PaymentChoice] = []
    let onOpenOrder: (() -> Void)?
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let onOpenOrder {
            Button(action: onOpenOrder) { content(showsChevron: true) }
                .buttonStyle(WalletRowButtonStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("wallet.entry.\(entry.id)")
        } else {
            content(showsChevron: false)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("wallet.entry.\(entry.id)")
        }
    }

    @ViewBuilder
    private func content(showsChevron: Bool) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    HStack {
                        WalletRowIcon(icon: Self.icon(entry.kind))
                        Spacer(minLength: 0)
                        if showsChevron { chevron }
                    }
                    texts
                    amount
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: TaleedSpacing.s12) {
                    WalletRowIcon(icon: Self.icon(entry.kind))
                    texts
                        .frame(maxWidth: .infinity, alignment: .leading)
                    amount
                        .lineLimit(1)
                        .layoutPriority(1)
                    if showsChevron {
                        chevron
                    } else {
                        Color.clear.frame(width: Self.chevronSize, height: 1).accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.vertical, TaleedSpacing.s12)
        .padding(.horizontal, TaleedSpacing.s12)
        .frame(minHeight: TaleedSize.touchTargetMin)
        .contentShape(Rectangle())
    }

    private static let chevronSize: CGFloat = 16

    private var chevron: some View {
        TaleedIconView(.caretRight, size: Self.chevronSize, color: TaleedColor.textSecondary)
            .accessibilityHidden(true)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            Text(verbatim: entry.label)
                .taleedFont(TaleedFont.bodyRegular.with(weight: .semibold))
                .foregroundStyle(TaleedColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: detail)
                .taleedFont(TaleedFont.bodySmall)
                .foregroundStyle(TaleedColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var amount: some View {
        Text(verbatim: WalletText.signedAmount(entry.amount, language: l10n.language))
            .taleedFont(TaleedFont.buttonMedium.with(weight: .extrabold))
            .monospacedDigit()
            .foregroundStyle(amountColor)
    }

    private var detail: String {
        WalletText.entryDetail(entry, locale: l10n.language.formattingLocale, topUpMethods: topUpMethods) { date in
            l10n.format(.referralsVoucherExpires, date)
        }
    }

    private var amountColor: Color {
        switch WalletRules.amountTone(entry) {
        case .credit: TaleedColor.feedbackSuccess
        case .debit: TaleedColor.feedbackError
        case .muted: TaleedColor.textSecondary
        }
    }

    /// The icon of a line's type (the design system has no wallet glyph: the nearest ones; vouchers the ticket, as on Referrals).
    static func icon(_ kind: WalletEntryKind) -> TaleedIcon {
        switch kind {
        case .saleRelease: .storefront
        case .payout: .money
        case .adjustment: .slidersHorizontal
        case .refundDebit: .arrowRight
        case .topUp: .plusCircle
        case .purchase: .tShirt
        case .purchaseRefund: .arrowLeft
        case .voucher: .ticket
        case .unknown: .money
        }
    }
}

/// A payout: the amount ("1 000 DA", the key figure, on its own line), "CCP · 4 oct. 2026, 14:32 ·
/// VIR-2026-0042", "Voir le justificatif" when the team attached a receipt, and the server's status as a
/// badge.
struct PayoutRowView: View {
    let payout: PayoutRow
    let onOpenProof: (() -> Void)?
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: TaleedSpacing.s12) {
            WalletRowIcon(icon: .money)
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                    Text(verbatim: PriceFormatter.format(payout.amount, language: l10n.language))
                        .taleedFont(TaleedFont.bodyRegular.with(weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(TaleedColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: WalletText.payoutDetail(payout, locale: l10n.language.formattingLocale))
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                if let onOpenProof {
                    TaleedButton(title: l10n.string(.walletViewProof), kind: .hyperlink, size: .small, action: onOpenProof)
                        .accessibilityIdentifier("wallet.payout.proof")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TaleedBadge(title: payout.statusLabel, tone: WalletRules.payoutTone(payout.status))
                .fixedSize()
        }
        .padding(TaleedSpacing.s12)
        .frame(minHeight: TaleedSize.touchTargetMin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet.payout.\(payout.id)")
    }
}

/// The line's icon in a 36 pt `brandSoft` circle.
private struct WalletRowIcon: View {
    let icon: TaleedIcon

    var body: some View {
        TaleedIconView(icon, size: 18, color: TaleedColor.brandPrimary)
            .frame(width: 36, height: 36)
            .background(Circle().fill(TaleedColor.brandSoft))
            .accessibilityHidden(true)
    }
}

private struct WalletRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? TaleedColor.surfaceGrouped : TaleedColor.surfacePrimary)
    }
}
