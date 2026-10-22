import SwiftUI

/// "Suivi de la commande": each step of the server with its label, done or not, and its date; the
/// carrier's scans folded under "Détails du transporteur", newest first, in the carrier's words.
struct OrderTimelineCard: View {
    let steps: [OrderStepInfo]
    let scans: [CarrierScan]
    @State private var showsScans = false
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                Text(l10n.string(.ordersTimeline))
                    .taleedFont(TaleedFont.headline)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: TaleedSpacing.s12) {
                        Group {
                            if step.done {
                                TaleedIconView(.checkCircle, size: 20, color: TaleedColor.feedbackSuccess)
                            } else {
                                Circle().strokeBorder(TaleedColor.borderSubtle, lineWidth: 1.5)
                                    .frame(width: 18, height: 18)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.label)
                                .taleedFont(TaleedFont.bodyRegular.with(weight: step.done ? .semibold : .regular))
                                .foregroundStyle(step.done ? TaleedColor.textPrimary : TaleedColor.textSecondarySmall)
                            if let date = step.date {
                                Text(OrderText.dateTime(date, locale: l10n.language.formattingLocale))
                                    .taleedFont(TaleedFont.caption)
                                    .foregroundStyle(TaleedColor.textSecondarySmall)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(step.done ? .isSelected : [])
                }
            }
            .padding(TaleedSpacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !scans.isEmpty {
                Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
                Button {
                    withAnimation(.easeInOut(duration: TaleedMotion.transitionMin)) { showsScans.toggle() }
                } label: {
                    HStack {
                        Text(l10n.string(.ordersCarrierDetails))
                            .taleedFont(TaleedFont.bodySmall.with(weight: .semibold))
                            .foregroundStyle(TaleedColor.textBody)
                        Spacer()
                        TaleedIconView(.caretDown, size: 16, color: TaleedColor.textSecondary)
                            .rotationEffect(.degrees(showsScans ? 180 : 0))
                    }
                    .padding(.horizontal, TaleedSpacing.s16)
                    .frame(minHeight: TaleedSize.touchTargetMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(showsScans ? .isSelected : [])
                .accessibilityIdentifier("order.carrierDetails")
                if showsScans {
                    VStack(spacing: 0) {
                        ForEach(scans) { scan in
                            HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    // The carrier's words in the brand font (only the tracking number is monospaced).
                                    Text(verbatim: scan.status)
                                        .taleedFont(TaleedFont.caption.with(weight: .semibold))
                                        .foregroundStyle(TaleedColor.textBody)
                                    if let place = scan.place {
                                        Text(verbatim: place)
                                            .taleedFont(TaleedFont.caption)
                                            .foregroundStyle(TaleedColor.textSecondarySmall)
                                    }
                                }
                                Spacer(minLength: TaleedSpacing.s8)
                                Text(OrderText.dateTime(scan.date, locale: l10n.language.formattingLocale))
                                    .taleedFont(TaleedFont.caption)
                                    .foregroundStyle(TaleedColor.textSecondarySmall)
                            }
                            .padding(.horizontal, TaleedSpacing.s16)
                            .padding(.vertical, TaleedSpacing.s8)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.bottom, TaleedSpacing.s8)
                }
            }
        }
        .taleedCard()
        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
    }
}

/// "Évaluations": the member's own review ("Vous") and the one the other side left about them.
struct OrderReviewsCard: View {
    let order: OrderDetailInfo
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        if order.myReview != nil || order.reviewReceived != nil {
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                Text(l10n.string(.reviewsTitle))
                    .taleedFont(TaleedFont.headline)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let review = order.myReview {
                    row(review, author: l10n.string(.commonYou))
                        .accessibilityIdentifier("order.myReview")
                }
                if let review = order.reviewReceived {
                    row(review, author: order.counterpart?.displayName.isolatedLeftToRight ?? l10n.string(.ordersDeletedAccount))
                        .accessibilityIdentifier("order.reviewReceived")
                }
            }
            .padding(TaleedSpacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .taleedCard()
        }
    }

    private func row(_ review: OrderReviewInfo, author: String) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            HStack(spacing: TaleedSpacing.s8) {
                Text(author)
                    .taleedFont(TaleedFont.bodyRegular.with(weight: .semibold))
                    .foregroundStyle(TaleedColor.textPrimary)
                RatingStarsView(value: review.rating)
                    .accessibilityElement()
                    .accessibilityLabel(l10n.format(.reviewsStars, review.rating))
                Spacer(minLength: 0)
                Text(OrderText.date(review.createdAt, locale: l10n.language.formattingLocale))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
            }
            if let comment = review.comment {
                Text(verbatim: "“\(comment)”")
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .naturalDirection(of: comment)
            }
        }
        .padding(TaleedSpacing.s12)
        .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
