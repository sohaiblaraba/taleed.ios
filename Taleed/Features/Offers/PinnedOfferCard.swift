import SwiftUI

/// The offer pinned under a conversation's item strip (screens.md §2 G10 screen 2): who offered what,
/// its status and time left, a bundle's item count, and only the buttons its flags allow: "Accepter",
/// "Refuser", "Contre-offre", "Annuler l'offre", "Payer maintenant · X" (website `offer-card.tsx`).
struct PinnedOfferCard: View {
    let pinned: PinnedOffer
    /// The other member's handle ("@amina"), for "@amina propose 4 000 DA".
    let counterpartName: String
    let now: Date
    let work: ConversationOfferWork?
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onCounter: () -> Void
    let onWithdraw: () -> Void
    let onPay: (CheckoutTarget) -> Void
    @Environment(LanguageManager.self) private var l10n

    private var offer: ChatOffer { pinned.offer }

    var body: some View {
        let status = offer.displayStatus(at: now)
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
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
                TaleedBadge(title: l10n.string(ChatText.offerStatusKey(status)), tone: ChatText.offerStatusTone(status))
                    .fixedSize()
            }
            Text(summary)
                .taleedFont(TaleedFont.sectionTitle)
                .foregroundStyle(TaleedColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("offer.pinned.summary")
            if status == .pending {
                let relative = RelativeTimeText.string(for: offer.expiresAt, now: now, locale: l10n.language.formattingLocale)
                Text(l10n.format(.offersExpiresIn, relative))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textBody)
            }
            if pinned.hasActions { actions }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.vertical, TaleedSpacing.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaleedColor.brandSoft)
        .overlay(alignment: .bottom) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offer.pinned")
    }

    @ViewBuilder
    private var actions: some View {
        if pinned.canAccept || pinned.canDecline {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TaleedSpacing.s8) { answerButtons }
                VStack(spacing: TaleedSpacing.s8) { answerButtons }
            }
        }
        if pinned.canCounter {
            TaleedButton(title: l10n.string(.offersCounter), kind: .tertiary, size: .medium,
                         isLoading: work == .counter(offerId: offer.id), isFullWidth: true, action: onCounter)
                .disabled(work != nil)
                .accessibilityIdentifier("offer.counter")
        }
        if let payment = pinned.payment {
            TaleedButton(title: "\(l10n.string(.offersPayNow)) · \(PriceFormatter.format(offer.amount, language: l10n.language))",
                         kind: .secondary, size: .large, isFullWidth: true) { onPay(payment) }
                .accessibilityIdentifier("offer.pay")
        }
        if pinned.canWithdraw {
            TaleedButton(title: l10n.string(.offersCancelOffer), kind: .hyperlink, size: .medium,
                         isLoading: isRunning(.withdraw), isFullWidth: true, action: onWithdraw)
                .disabled(work != nil)
                .accessibilityIdentifier("offer.withdraw")
        }
    }

    @ViewBuilder
    private var answerButtons: some View {
        if pinned.canAccept {
            TaleedButton(title: l10n.string(.offersAccept), kind: .primary, size: .medium, isLoading: isRunning(.accept),
                         isFullWidth: true, action: onAccept)
                .disabled(work != nil)
                .accessibilityIdentifier("offer.accept")
        }
        if pinned.canDecline {
            TaleedButton(title: l10n.string(.offersDecline), kind: .outline, size: .medium, isLoading: isRunning(.decline),
                         isFullWidth: true, action: onDecline)
                .disabled(work != nil)
                .accessibilityIdentifier("offer.decline")
        }
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
/// "Accepter" confirmation.
struct ConversationPinnedOffer: View {
    let model: ConversationViewModel
    let counterpartName: String?
    @Binding var sheet: ConversationOfferSheet?
    @Binding var accepting: ChatOffer?
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let pinned = model.pinnedOffer {
            PinnedOfferCard(pinned: pinned, counterpartName: counterpartName ?? l10n.string(.chatDeletedUser),
                            now: model.currentDate, work: model.offerWork,
                            onAccept: { accepting = pinned.offer },
                            onDecline: { respond(.decline, to: pinned.offer) },
                            onCounter: { sheet = .counter(pinned.offer) },
                            onWithdraw: { respond(.withdraw, to: pinned.offer) },
                            onPay: { router.pushSignedIn(.checkout($0)) })
        }
    }

    /// "Refuser" or "Annuler l'offre": no confirmation, as on the website (§7 G10).
    private func respond(_ response: OfferResponse, to offer: ChatOffer) {
        Task { _ = await model.respond(response, to: offer) }
    }
}
