import SwiftUI

// The wallet screen's header (screens.md §7 G14): the top-up result, the tiles, the actions, and the
// skeleton of all three with the tabs while the wallet loads.

/// "Recharger" (mint, the website's CTA) and "Demander un virement" (blue), side by side when they fit,
/// stacked otherwise; "Minimum : 100 DA" right under the payout button, centred, while the balance is
/// under the minimum (the reason that button is off). Without a summary (loading): placeholders of the
/// same size, side by side or stacked as the buttons will be.
struct WalletActions: View {
    let summary: WalletSummary?
    var onTopUp: () -> Void = {}
    var onPayout: () -> Void = {}
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TaleedSpacing.s12) { buttons }
            VStack(spacing: TaleedSpacing.s12) { buttons }
        }
    }

    private var showsTopUp: Bool { summary.map(WalletRules.showsTopUp) ?? true }

    private var canRequestPayout: Bool { summary.map(WalletRules.canRequestPayout) ?? true }

    private var minimumText: String? {
        guard let summary, !canRequestPayout else { return nil }
        return l10n.format(.walletMinPayout, PriceFormatter.format(summary.limits.minPayout, language: l10n.language))
    }

    @ViewBuilder
    private var buttons: some View {
        if showsTopUp {
            TaleedButton(title: l10n.string(.walletTopUp), kind: .secondary, size: .large, leadingIcon: .plusCircle,
                         isFullWidth: true, action: onTopUp)
                .skeletonPlaceholder(summary == nil)
                .accessibilityIdentifier("wallet.topUp")
        }
        VStack(spacing: TaleedSpacing.s4) {
            TaleedButton(title: l10n.string(.walletRequestPayout), kind: .primary, size: .large, leadingIcon: .money,
                         isFullWidth: true, action: onPayout)
                .disabled(!canRequestPayout)
                .accessibilityHint(minimumText ?? "")
                .skeletonPlaceholder(summary == nil)
                .accessibilityIdentifier("wallet.requestPayout")
            if let minimumText {
                Text(minimumText)
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wallet.minPayout")
            }
        }
    }
}

/// The two tiles of the website, in one bordered card: "Solde disponible" (balance plus vouchers, with
/// the voucher part) and "En attente (commandes en cours)", muted, with its hint. Without a summary
/// (loading): the same card with placeholders for the amounts.
struct WalletTiles: View {
    let summary: WalletSummary?
    @Environment(LanguageManager.self) private var l10n
    /// The eyebrows' and the notes' icons grow with the text (capped), on the first line of their label.
    @ScaledMetric(relativeTo: .caption2) private var eyebrowIconSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var noteIconSize: CGFloat = 12

    static let headlineStyle = TaleedTextStyle(size: 28, weight: .extrabold, lineHeight: nil, letterSpacing: 0, relativeTo: .title)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tile(icon: .money, title: l10n.string(.walletBalance), amount: summary?.headline, color: TaleedColor.textPrimary,
                 note: voucherNote)
                .accessibilityIdentifier("wallet.balance")
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
            tile(icon: .lockKey, title: l10n.string(.walletPendingEscrow), amount: summary?.pendingEscrow,
                 color: TaleedColor.textSecondary, note: (.info, l10n.string(.walletPendingHint)))
                .accessibilityIdentifier("wallet.pending")
        }
        .taleedCard(radius: TaleedRadius.l)
    }

    /// "dont 500 DA en bons d'achat (non retirables)".
    private var voucherNote: (TaleedIcon, String)? {
        guard let summary, WalletRules.showsVoucherPart(summary) else { return nil }
        return (.ticket, l10n.format(.walletVoucherPart, PriceFormatter.format(summary.voucherBalance, language: l10n.language)))
    }

    private func tile(icon: TaleedIcon, title: String, amount: Int?, color: Color, note: (TaleedIcon, String)?) -> some View {
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
            if let note {
                HStack(alignment: .top, spacing: TaleedSpacing.s4) {
                    FirstLineIcon(icon: note.0, size: min(noteIconSize, 24), textStyle: TaleedFont.bodySmall)
                    Text(note.1)
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The top-up's result, as the website's banners; "Vérification du paiement…" while the sync runs.
struct TopUpBannerView: View {
    let banner: TopUpBanner
    let onDismiss: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        Group {
            switch banner {
            case .checking:
                HStack(spacing: TaleedSpacing.s12) {
                    ProgressView().tint(TaleedColor.brandPrimary)
                    Text(l10n.string(.appCheckoutVerifying))
                        .taleedFont(TaleedFont.bodyLarge)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(TaleedSize.alertPadding)
                .background(TaleedColor.brandTintStrong, in: RoundedRectangle(cornerRadius: TaleedSize.alertRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            case .paid:
                InlineAlert(kind: .success, title: l10n.string(.walletToppedUp), actionTitle: l10n.string(.commonDismiss),
                            action: onDismiss)
            case .pending:
                InlineAlert(kind: .info, title: l10n.string(.walletTopUpPending), actionTitle: l10n.string(.commonDismiss),
                            action: onDismiss)
            case .failed:
                InlineAlert(kind: .error, title: l10n.string(.walletTopUpFailed), actionTitle: l10n.string(.commonDismiss),
                            action: onDismiss)
            }
        }
        .accessibilityIdentifier("wallet.banner")
        .onAppear { announce() }
        .onChange(of: banner) { _, _ in announce() }
    }

    private func announce() {
        let text: String = switch banner {
        case .checking: l10n.string(.appCheckoutVerifying)
        case .paid: l10n.string(.walletToppedUp)
        case .pending: l10n.string(.walletTopUpPending)
        case .failed: l10n.string(.walletTopUpFailed)
        }
        AccessibilityNotification.Announcement(text).post()
    }
}

/// The header's shape while it loads (design-system §3.6 "Preserve layout · avoid jump"): the tiles'
/// card with placeholders for the two amounts, the buttons' placeholders laid out as the buttons will be
/// (side by side or stacked), and the tabs, so nothing moves when the wallet arrives.
struct WalletSkeleton: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                    WalletTiles(summary: nil)
                    WalletActions(summary: nil)
                }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.top, TaleedSpacing.s16)
                .padding(.bottom, TaleedSpacing.s24)
                TaleedTabs(titles: [l10n.string(.walletHistory), l10n.string(.walletPayouts)], selection: .constant(0))
                    .allowsHitTesting(false)
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
