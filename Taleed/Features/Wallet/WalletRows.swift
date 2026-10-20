import SwiftUI

/// The "Historique" tab: its states, then the lines in one bordered card, as the website's list.
struct WalletHistorySection: View {
    let list: PagedList<WalletEntryRow>
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router

    var body: some View {
        WalletListSection(list: list) { entry in
            WalletEntryRowView(entry: entry, onOpenOrder: entry.orderId.map { id in { router.push(.order(id: id)) } })
        }
    }
}

/// The "Virements" tab.
struct WalletPayoutsSection: View {
    let list: PagedList<PayoutRow>
    @Environment(AppRouter.self) private var router

    var body: some View {
        WalletListSection(list: list) { payout in
            PayoutRowView(payout: payout, onOpenProof: payout.proofURL.map { url in { router.openInBrowser(url) } })
        }
    }
}

/// A tab's list: a spinner while the first page loads, the error with Retry, "Aucune opération pour le
/// moment." when empty, otherwise the rows with dividers, then the pagination footer as a sibling in the
/// screen's lazy stack.
private struct WalletListSection<Item: Identifiable & Sendable, Row: View>: View where Item.ID: Sendable {
    let list: PagedList<Item>
    @ViewBuilder let row: (Item) -> Row
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s12) {
            if list.hasLoaded {
                if list.items.isEmpty {
                    Text(l10n.string(.walletNoEntries))
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, TaleedSpacing.s16)
                        .padding(.vertical, TaleedSpacing.s32)
                        .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
                                .strokeBorder(TaleedColor.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                        .padding(.horizontal, TaleedLayout.screenMargin)
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
/// the date and "Expire le …" while active), and the signed amount. A line about an order opens it.
struct WalletEntryRowView: View {
    let entry: WalletEntryRow
    let onOpenOrder: (() -> Void)?
    @Environment(LanguageManager.self) private var l10n

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

    private func content(showsChevron: Bool) -> some View {
        HStack(spacing: TaleedSpacing.s12) {
            WalletRowIcon(icon: Self.icon(entry.kind))
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
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: WalletText.signedAmount(entry.amount, language: l10n.language))
                .taleedFont(TaleedFont.buttonMedium.with(weight: .extrabold))
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .layoutPriority(1)
            if showsChevron {
                TaleedIconView(.caretRight, size: 16, color: TaleedColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, TaleedSpacing.s12)
        .padding(.horizontal, TaleedSpacing.s12)
        .frame(minHeight: TaleedSize.touchTargetMin)
        .contentShape(Rectangle())
    }

    private var detail: String {
        WalletText.entryDetail(entry, locale: l10n.language.formattingLocale) { date in
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

/// A payout: "CCP · 1 000 DA", "4 oct. 2026 · VIR-2026-0042", "Voir le justificatif" when the team
/// attached a receipt, and the server's status as a badge.
struct PayoutRowView: View {
    let payout: PayoutRow
    let onOpenProof: (() -> Void)?
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: TaleedSpacing.s12) {
            WalletRowIcon(icon: .money)
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                    Text(verbatim: "\(payout.methodLabel) · \(PriceFormatter.format(payout.amount, language: l10n.language))")
                        .taleedFont(TaleedFont.bodyRegular.with(weight: .semibold))
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
