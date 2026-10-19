import SwiftUI

/// How much of the pinned offer shows (G10, app-guidelines "large text"): the whole card, or one row
/// (status, amount, one action) while the keyboard is up and at accessibility text sizes, so that the
/// thread stays readable. A caret switches between the two where both are offered.
enum PinnedOfferLayout: Equatable {
    /// The whole card, no caret.
    case full
    /// One row and one action, with a caret that shows the whole card.
    case compact
    /// The whole card, with a caret that brings the row back.
    case expanded

    /// While the member types, the row; at accessibility sizes, the row until the member expands it.
    static func of(isComposing: Bool, isAccessibilitySize: Bool, isExpanded: Bool) -> PinnedOfferLayout {
        if isComposing { return .compact }
        guard isAccessibilitySize else { return .full }
        return isExpanded ? .expanded : .compact
    }
}

/// The one action the compact row keeps: paying, then answering, then countering, then withdrawing.
enum PinnedOfferMainAction: Equatable {
    case pay(CheckoutTarget)
    case accept
    case counter
    case withdraw

    init?(_ pinned: PinnedOffer) {
        if let payment = pinned.payment {
            self = .pay(payment)
        } else if pinned.canAccept {
            self = .accept
        } else if pinned.canCounter {
            self = .counter
        } else if pinned.canWithdraw {
            self = .withdraw
        } else {
            return nil
        }
    }
}

/// The offer pinned under a conversation's item strip (screens.md §2 G10 screen 2): who offered what,
/// its status and time left, a bundle's item count, and only the buttons its flags allow: "Accepter",
/// "Refuser", "Contre-offre", "Annuler l'offre", "Payer maintenant · X" (website `offer-card.tsx`).
struct PinnedOfferCard: View {
    let pinned: PinnedOffer
    /// The other member's handle ("@amina"), for "@amina propose 4 000 DA".
    let counterpartName: String
    let now: Date
    let work: ConversationOfferWork?
    var layout: PinnedOfferLayout = .full
    /// The caret: shows the whole card or the row again.
    var onToggleLayout: () -> Void = {}
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onCounter: () -> Void
    let onWithdraw: () -> Void
    let onPay: (CheckoutTarget) -> Void
    @Environment(LanguageManager.self) private var l10n

    private var offer: ChatOffer { pinned.offer }

    var body: some View {
        Group {
            if layout == .compact { compactCard } else { fullCard }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.vertical, layout == .compact ? TaleedSpacing.s8 : TaleedSpacing.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaleedColor.brandSoft)
        .overlay(alignment: .bottom) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offer.pinned")
    }

    // MARK: Compact

    /// The status, the amount and the caret on one row, then the main action.
    private var compactCard: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            HStack(alignment: .center, spacing: TaleedSpacing.s8) {
                statusBadge
                Text(PriceFormatter.format(offer.amount, language: l10n.language))
                    .taleedFont(TaleedFont.sectionTitle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(summary)
                    .accessibilityIdentifier("offer.pinned.summary")
                Spacer(minLength: 0)
                layoutCaret
            }
            if let main = PinnedOfferMainAction(pinned) { mainButton(main) }
        }
    }

    @ViewBuilder
    private func mainButton(_ action: PinnedOfferMainAction) -> some View {
        switch action {
        case let .pay(payment): payButton(payment)
        case .accept: acceptButton
        case .counter: counterButton
        case .withdraw: withdrawButton
        }
    }

    /// 44 pt; "Afficher toute l'offre" or "Réduire l'offre".
    @ViewBuilder
    private var layoutCaret: some View {
        if layout != .full {
            Button(action: onToggleLayout) {
                TaleedIconView(.caretDown, size: 20, color: TaleedColor.textPrimary)
                    .rotationEffect(.degrees(layout == .expanded ? 180 : 0))
                    .frame(width: TaleedSize.iconButtonSize, height: TaleedSize.iconButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l10n.string(layout == .compact ? .appOfferShowDetails : .appOfferHideDetails))
            .accessibilityIdentifier("offer.pinned.layout")
        }
    }

    private var statusBadge: some View {
        let status = offer.displayStatus(at: now)
        return TaleedBadge(title: l10n.string(ChatText.offerStatusKey(status)), tone: ChatText.offerStatusTone(status))
            .fixedSize()
    }

    // MARK: Full

    private var fullCard: some View {
        let status = offer.displayStatus(at: now)
        return VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            HStack(alignment: .center, spacing: TaleedSpacing.s8) {
                HStack(spacing: TaleedSpacing.s4) {
                    TaleedIconView(offer.bundle == nil ? .money : .storefront, size: 14, color: TaleedColor.textBody)
                    Text(eyebrow.uppercased(with: l10n.language.locale))
                        .taleedFont(TaleedFont.eyebrow)
                        .foregroundStyle(TaleedColor.textBody)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                statusBadge
                layoutCaret
            }
            Text(summary)
                .taleedFont(TaleedFont.sectionTitle)
                .foregroundStyle(TaleedColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("offer.pinned.summary")
            if status == .pending {
                // The time left, every minute (the card itself redraws when the offer lapses).
                TimelineView(.everyMinute) { context in
                    let relative = RelativeTimeText.string(for: offer.expiresAt, now: max(context.date, now),
                                                           locale: l10n.language.formattingLocale)
                    Text(l10n.format(.offersExpiresIn, relative))
                        .taleedFont(TaleedFont.caption)
                        .foregroundStyle(TaleedColor.textBody)
                }
            }
            if pinned.hasActions { actions }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if pinned.canAccept || pinned.canDecline {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TaleedSpacing.s8) { answerButtons }
                VStack(spacing: TaleedSpacing.s8) { answerButtons }
            }
        }
        if pinned.canCounter { counterButton }
        if let payment = pinned.payment { payButton(payment) }
        if pinned.canWithdraw { withdrawButton }
    }

    @ViewBuilder
    private var answerButtons: some View {
        if pinned.canAccept { acceptButton }
        if pinned.canDecline {
            TaleedButton(title: l10n.string(.offersDecline), kind: .outline, size: .medium, isLoading: isRunning(.decline),
                         isFullWidth: true, action: onDecline)
                .disabled(work != nil)
                .accessibilityIdentifier("offer.decline")
        }
    }

    // MARK: Buttons

    private var acceptButton: some View {
        TaleedButton(title: l10n.string(.offersAccept), kind: .primary, size: .medium, isLoading: isRunning(.accept),
                     isFullWidth: true, action: onAccept)
            .disabled(work != nil)
            .accessibilityIdentifier("offer.accept")
    }

    private var counterButton: some View {
        TaleedButton(title: l10n.string(.offersCounter), kind: .tertiary, size: .medium,
                     isLoading: work == .counter(offerId: offer.id), isFullWidth: true, action: onCounter)
            .disabled(work != nil)
            .accessibilityIdentifier("offer.counter")
    }

    private func payButton(_ payment: CheckoutTarget) -> some View {
        TaleedButton(title: "\(l10n.string(.offersPayNow)) · \(PriceFormatter.format(offer.amount, language: l10n.language))",
                     kind: .secondary, size: layout == .compact ? .medium : .large, isFullWidth: true) { onPay(payment) }
            .accessibilityIdentifier("offer.pay")
    }

    private var withdrawButton: some View {
        TaleedButton(title: l10n.string(.offersCancelOffer), kind: .hyperlink, size: .medium,
                     isLoading: isRunning(.withdraw), isFullWidth: true, action: onWithdraw)
            .disabled(work != nil)
            .accessibilityIdentifier("offer.withdraw")
    }

    private func isRunning(_ response: OfferResponse) -> Bool {
        work == .respond(response, offerId: offer.id)
    }

    /// "Offre sur un lot · 2 articles", "Faire une offre" or "Offre du vendeur" (§7 G9).
    private var eyebrow: String {
        switch ChatText.offerEyebrow(offer) {
        case let .bundle(count): l10n.format(.offersBundleOffer, count)
        case .buyer: l10n.string(.offersMakeOffer)
        case .seller: l10n.string(.offersSellerOffer)
        }
    }

    /// "Vous avez proposé 4 000 DA" or "@amina propose 4 000 DA".
    private var summary: String {
        let amount = PriceFormatter.format(offer.amount, language: l10n.language)
        return offer.isMine
            ? l10n.format(.offersYouOffered, amount)
            : l10n.format(.offersTheyOffered, counterpartName.isolatedLeftToRight, amount)
    }
}

/// The conversation's pinned offer (G10), when there is one, wired to the screen's sheets and the
/// "Accepter" confirmation. One row while the member types and at accessibility text sizes.
struct ConversationPinnedOffer: View {
    let model: ConversationViewModel
    let counterpartName: String?
    /// The keyboard is up for the composer.
    let isComposing: Bool
    @Binding var sheet: ConversationOfferSheet?
    @Binding var accepting: ChatOffer?
    /// Closes the keyboard, when the member asks for the whole card while typing.
    let endComposing: () -> Void
    @State private var isExpanded = false
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let pinned = model.pinnedOffer {
            let layout = PinnedOfferLayout.of(isComposing: isComposing, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                              isExpanded: isExpanded)
            PinnedOfferCard(pinned: pinned, counterpartName: counterpartName ?? l10n.string(.chatDeletedUser),
                            now: model.currentDate, work: model.offerWork, layout: layout,
                            onToggleLayout: { toggle(from: layout) },
                            onAccept: { accepting = pinned.offer },
                            onDecline: { respond(.decline, to: pinned.offer) },
                            onCounter: { sheet = .counter(pinned.offer) },
                            onWithdraw: { respond(.withdraw, to: pinned.offer) },
                            onPay: { router.pushSignedIn(.checkout($0)) })
        }
    }

    private func toggle(from layout: PinnedOfferLayout) {
        if layout == .compact {
            isExpanded = true
            if isComposing { endComposing() }
        } else {
            isExpanded = false
        }
    }

    /// "Refuser" or "Annuler l'offre": no confirmation, as on the website (§7 G10).
    private func respond(_ response: OfferResponse, to offer: ChatOffer) {
        Task { _ = await model.respond(response, to: offer) }
    }
}
