import SwiftUI

// The top of Earnings (slice H; the website's `/wallet` page): the weekly note, the three amounts, the
// payout details card, the vouchers with their rules, and the skeleton of all of them with the tabs
// while the summary loads. No button here adds, spends or withdraws money.

/// "Every Monday, Taleed pays everything owed to you to your payout details." under the title.
struct EarningsWeeklyNote: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        Text(l10n.string(.walletWeeklyNote))
            .taleedFont(TaleedFont.bodyRegular)
            .foregroundStyle(TaleedColor.textBody)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("wallet.weeklyNote")
    }
}

/// The website's three tiles, in one bordered card: "Owed to you" (red when negative) with the next
/// payout's date and the note that says why it waits, "In payout", and "In progress", muted. Without a
/// summary (loading): the same card with placeholders for the amounts.
struct WalletTiles: View {
    let summary: WalletSummary?
    @Environment(LanguageManager.self) private var l10n
    /// The eyebrows' and the notes' icons grow with the text (capped), on the first line of their label.
    @ScaledMetric(relativeTo: .caption2) private var eyebrowIconSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var noteIconSize: CGFloat = 12

    static let headlineStyle = TaleedTextStyle(size: 28, weight: .extrabold, lineHeight: nil, letterSpacing: 0, relativeTo: .title)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tile(icon: .money, title: l10n.string(.walletOwed), amount: summary?.owed, color: owedColor,
                 notes: owedNotes, emphasis: owedEmphasis)
                .accessibilityIdentifier("wallet.owed")
            divider
            tile(icon: .arrowUpRight, title: l10n.string(.walletInPayout), amount: summary?.inPayout, color: TaleedColor.textPrimary,
                 notes: [(.info, l10n.string(.walletInPayoutHint))])
                .accessibilityIdentifier("wallet.inPayout")
            divider
            tile(icon: .lockKey, title: l10n.string(.walletPendingEscrow), amount: summary?.inProgress,
                 color: TaleedColor.textSecondary, notes: [(.info, l10n.string(.walletPendingHint))])
                .accessibilityIdentifier("wallet.inProgress")
        }
        .taleedCard(radius: TaleedRadius.l)
    }

    private var divider: some View {
        Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
    }

    private var owedColor: Color {
        (summary?.owed ?? 0) < 0 ? TaleedColor.feedbackError : TaleedColor.textPrimary
    }

    /// "Paid with the next weekly payout, on 2 Nov 2026."
    private var owedNotes: [(TaleedIcon, String)] {
        guard let summary, WalletRules.showsNextPayoutDate(summary) else { return [] }
        let date = OrderText.date(summary.nextPayoutAt, locale: l10n.language.formattingLocale)
        return [(.clock, l10n.format(.walletOwedHint, date))]
    }

    /// Why the next run will not pay it: in the body colour, a little bolder, as the website's.
    private var owedEmphasis: String? {
        guard let summary, let note = WalletRules.owedNote(summary) else { return nil }
        return switch note {
        case .negative: l10n.string(.walletOwedNegative)
        case .needsDetails: l10n.string(.walletOwedNeedsDetails)
        case let .belowMinimum(minimum): l10n.format(.walletOwedBelowMin, PriceFormatter.format(minimum, language: l10n.language))
        }
    }

    private func tile(icon: TaleedIcon, title: String, amount: Int?, color: Color, notes: [(TaleedIcon, String)],
                      emphasis: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            HStack(alignment: .top, spacing: 6) {
                FirstLineIcon(icon: icon, size: min(eyebrowIconSize, 24), textStyle: TaleedFont.eyebrow)
                Text(title.uppercased(with: l10n.language.locale))
                    .taleedFont(TaleedFont.eyebrow)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(title)
            }
            // A small uppercase label: it stops growing at Accessibility 1 (as `Eyebrow`) rather than break
            // its words over huge lines.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            PriceText(amount: amount ?? 88_888, style: Self.headlineStyle, color: color)
                .skeletonPlaceholder(amount == nil)
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: TaleedSpacing.s4) {
                    FirstLineIcon(icon: note.0, size: min(noteIconSize, 24), textStyle: TaleedFont.bodySmall)
                    Text(note.1)
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let emphasis {
                Text(emphasis)
                    .taleedFont(TaleedFont.bodySmall.with(weight: .semibold))
                    .foregroundStyle(TaleedColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wallet.owedNote")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Payout details": the saved method and account details (left to right, as a number reads) with
/// "Updated {date}", or "No payout details yet."; the purpose line; then "Add payout details" (blue) or
/// "Change" (outline), which opens the sheet.
struct PayoutDetailsCard: View {
    let account: PayoutAccountInfo?
    let onEdit: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            Text(l10n.string(.walletPayoutDetailsTitle))
                .taleedFont(TaleedFont.bodyRegular.with(weight: .semibold))
                .foregroundStyle(TaleedColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let account {
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                    Text(verbatim: account.methodLabel)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textPrimary)
                    Text(verbatim: account.accountDetails.isolatedLeftToRight)
                        .taleedFont(TaleedFont.bodySmall)
                        .monospaced()
                        .foregroundStyle(TaleedColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Text(l10n.format(.walletPayoutDetailsUpdated,
                                     OrderText.date(account.updatedAt, locale: l10n.language.formattingLocale)))
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("wallet.payoutAccount")
            } else {
                Text(l10n.string(.walletPayoutDetailsEmpty))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                    .accessibilityIdentifier("wallet.payoutAccountEmpty")
            }
            PayoutDetailsPurpose()
            TaleedButton(title: l10n.string(account == nil ? .walletPayoutDetailsAdd : .walletPayoutDetailsEdit),
                         kind: account == nil ? .primary : .outline, size: .medium, leadingIcon: .money, action: onEdit)
                .padding(.top, TaleedSpacing.s4)
                .accessibilityIdentifier("wallet.editPayoutDetails")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .taleedCard(radius: TaleedRadius.l)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet.payoutDetails")
    }
}

/// "Used only to send your payouts and bank refunds." with the shield (Apple 5.1.1(i): what the data is for).
struct PayoutDetailsPurpose: View {
    @Environment(LanguageManager.self) private var l10n
    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: TaleedSpacing.s4) {
            FirstLineIcon(icon: .shieldCheck, size: min(iconSize, 24), textStyle: TaleedFont.bodySmall)
            Text(l10n.string(.walletPayoutDetailsPurpose))
                .taleedFont(TaleedFont.bodySmall)
                .foregroundStyle(TaleedColor.textSecondarySmall)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("payoutDetails.purpose")
    }
}

/// "Vouchers": the active total or "No active vouchers.", then "Voucher rules" (Google Play's rule for
/// loyalty programs: the rules are published in the app) on a grouped panel.
struct VouchersCard: View {
    let voucherBalance: Int
    let rules: VoucherRulesInfo
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            HStack(alignment: .center, spacing: 6) {
                TaleedIconView(.ticket, size: 16, color: TaleedColor.brandPrimary)
                    .accessibilityHidden(true)
                Text(l10n.string(.walletVouchersTitle))
                    .taleedFont(TaleedFont.bodyRegular.with(weight: .semibold))
                    .foregroundStyle(TaleedColor.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(voucherBalance > 0
                 ? l10n.format(.walletVouchersActive, PriceFormatter.format(voucherBalance, language: l10n.language))
                 : l10n.string(.walletVouchersEmpty))
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wallet.vouchersActive")
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Text(l10n.string(.walletVoucherRulesTitle))
                    .taleedFont(TaleedFont.bodySmall.with(weight: .semibold))
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(rulesText)
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(TaleedColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(TaleedSpacing.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("wallet.voucherRules")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .taleedCard(radius: TaleedRadius.l)
        .accessibilityIdentifier("wallet.vouchers")
    }

    private var rulesText: String {
        l10n.format(.walletVoucherRules, PriceFormatter.format(rules.voucherAmount, language: l10n.language),
                    PriceFormatter.format(rules.minItemPrice, language: l10n.language), rules.validityDays)
    }
}

/// The top's shape while it loads (design-system §3.6 "Preserve layout · avoid jump"): the note, the
/// tiles' card with placeholders for the amounts, and the tabs, so nothing moves when the summary arrives.
struct WalletSkeleton: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                    EarningsWeeklyNote()
                    WalletTiles(summary: nil)
                }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.top, TaleedSpacing.s16)
                .padding(.bottom, TaleedSpacing.s24)
            }
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(.commonLoading))
        .accessibilityIdentifier("wallet.loading")
    }
}

private extension View {
    /// While loading: the view's space, drawn as a pulsing placeholder of its shape.
    @ViewBuilder
    func skeletonPlaceholder(_ isPlaceholder: Bool) -> some View {
        if isPlaceholder {
            hidden()
                .overlay {
                    RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
                        .fill(TaleedColor.skeleton)
                        .skeletonPulse()
                }
                .allowsHitTesting(false)
        } else {
            self
        }
    }
}
