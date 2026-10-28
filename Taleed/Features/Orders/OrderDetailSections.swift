import SwiftUI

/// The status badge with the server's label, and the date of the order: at the end of the row, or
/// under the badge from accessibility text sizes on (the date never breaks).
struct OrderStatusHeader: View {
    let order: OrderDetailInfo
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    badge
                    date
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: TaleedSpacing.s8) {
                    badge
                    Spacer(minLength: TaleedSpacing.s8)
                    date
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        TaleedBadge(title: order.statusLabel, tone: order.status.badgeTone)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("order.status")
    }

    private var date: some View {
        Text(OrderText.date(order.createdAt, locale: l10n.language.formattingLocale))
            .taleedFont(TaleedFont.caption)
            .foregroundStyle(TaleedColor.textSecondarySmall)
    }
}

/// The notices above the order (the website's banners), as inline alerts.
struct OrderNoticesView: View {
    let order: OrderDetailInfo
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        let notices = OrderRules.notices(for: order)
        if !notices.isEmpty {
            VStack(spacing: TaleedSpacing.s8) {
                ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
                    alert(notice)
                }
            }
            .accessibilityIdentifier("order.notices")
        }
    }

    @ViewBuilder
    private func alert(_ notice: OrderRules.Notice) -> some View {
        let locale = l10n.language.formattingLocale
        let price = { (amount: Int) in PriceFormatter.format(amount, language: l10n.language) }
        switch notice {
        case let .ended(refunded):
            InlineAlert(kind: .info, title: l10n.string(refunded ? .appOrderRefundedNotice : .ordersCancelled))
                .accessibilityIdentifier("order.ended")
        case let .payDeadline(date):
            InlineAlert(kind: .warning, title: l10n.format(.ordersPayDeadline, OrderText.dateTime(date, locale: locale)))
        case let .awaitingPayment(date):
            InlineAlert(kind: .warning, title: l10n.format(.ordersAwaitingPaymentSeller, OrderText.dateTime(date, locale: locale)))
        case let .sellerShipsBy(date, cashOnDelivery):
            InlineAlert(kind: .info, title: l10n.format(cashOnDelivery ? .appOrderSellerShipsByCod : .appOrderSellerShipsBy,
                                                        OrderText.date(date, locale: locale)))
        case let .shipBy(date):
            InlineAlert(kind: .info, title: l10n.format(.ordersShipBy, OrderText.date(date, locale: locale)))
        case let .dropOffBy(date):
            InlineAlert(kind: .warning, title: l10n.format(.ordersDropOffBy, OrderText.date(date, locale: locale)))
        case let .cashOnDelivery(cash):
            // The pick-up notice's shape: a short title, the amounts under it.
            let notice = OrderText.titled(cash.deliveryFee > 0
                ? l10n.format(.ordersCodNotice, price(cash.total - cash.deliveryFee), price(cash.deliveryFee))
                : l10n.format(.ordersCodNoticeIncluded, price(cash.total)))
            InlineAlert(kind: .info, title: notice.title, message: notice.body)
        case let .pickupReady(place):
            InlineAlert(kind: .info, title: l10n.string(.ordersPickupReadyTitle),
                        message: l10n.format(order.side == .seller ? .ordersPickupReadySeller : .ordersPickupReadyBuyer,
                                             place.isolatedByContent))
        case let .autoRelease(date):
            InlineAlert(kind: .success, title: l10n.format(.ordersAutoReleaseOn, OrderText.dateTime(date, locale: locale)))
        }
    }
}

/// The dispute on the order. Open: the website's banner (funds frozen) with the reason and status from the
/// server, who must answer and until when. Resolved: how it ended as the title ("Litige résolu —
/// remboursement"), the reason and the resolution under it. Then the thread.
struct OrderDisputeCard: View {
    let dispute: OrderDisputeSummary
    let side: OrderSide
    let onOpenThread: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InlineAlert(kind: dispute.status.isResolved ? .info : .error, title: title, message: details)
                .padding(TaleedSpacing.s8)
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
            ListRow(label: l10n.string(.disputesThread), leadingIcon: .chatCircleText, showsChevron: true, showsDivider: false,
                    action: onOpenThread)
                .accessibilityIdentifier("order.disputeThread")
        }
        .taleedCard()
        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch dispute.status {
        case .resolvedRefund: l10n.string(.appOrderDisputeResolvedRefund)
        case .resolvedRelease: l10n.string(.appOrderDisputeResolvedRelease)
        case .open, .underReview, .unknown: l10n.string(.ordersDisputeBanner)
        }
    }

    /// "Article endommagé — Ouvert", then the deadline; once resolved, the reason (the title says how it
    /// ended), then the resolution.
    private var details: String {
        var lines = [dispute.status.isResolved ? dispute.reasonLabel : "\(dispute.reasonLabel) — \(dispute.statusLabel)"]
        if dispute.status == .open, let deadline = dispute.sellerDeadlineAt {
            let date = OrderText.dateTime(deadline, locale: l10n.language.formattingLocale)
            lines.append(l10n.format(side == .seller ? .disputesAwaitingYou : .disputesAwaitingSeller, date))
        }
        if let resolution = dispute.resolution {
            lines.append("\(l10n.string(.disputesResolution)): \(resolution)")
        }
        return lines.joined(separator: "\n")
    }
}

/// The goods and the other member: one item with its photo and title (opens the listing), or
/// "Lot · n articles" and each item with the price it was bought at; then "Vendeur @amina" (opens the
/// profile) or "Compte supprimé", and the amount (the total for the buyer, what the seller receives).
struct OrderGoodsCard: View {
    let order: OrderDetailInfo
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            if dynamicTypeSize.isAccessibilitySize {
                // Stacked: nothing shares a line with the title, the amount or the member.
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                    thumbnail
                    title
                    amount
                    counterpart
                }
            } else {
                // The member's row spans the width under the title and the amount: a long handle is
                // cut only when it does not fit there.
                HStack(alignment: .top, spacing: TaleedSpacing.s12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        HStack(alignment: .top, spacing: TaleedSpacing.s12) {
                            title
                                .frame(maxWidth: .infinity, alignment: .leading)
                            amount
                                .layoutPriority(1)
                        }
                        counterpart
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if order.isBundle {
                Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
                ForEach(order.items) { item in
                    Button { openListing(item.listingId) } label: {
                        HStack(spacing: TaleedSpacing.s12) {
                            RemoteImage(url: item.imageURL)
                                .frame(width: 40, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.xs, style: .continuous))
                            Text(verbatim: item.title.isolatedByContent)
                                .taleedFont(TaleedFont.bodyRegular)
                                .foregroundStyle(TaleedColor.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PriceText(amount: item.price, style: TaleedFont.bodyRegular)
                        }
                        .frame(minHeight: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("order.item.\(item.listingId)")
                }
            }
        }
        .padding(TaleedSpacing.s16)
        .taleedCard()
    }

    private var thumbnail: some View {
        Button { openListing(order.items.first?.listingId) } label: {
            RemoteImage(url: order.imageURL)
                .frame(width: TaleedSize.checkoutThumbWidth, height: TaleedSize.checkoutThumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: TaleedSize.checkoutThumbRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(order.isBundle)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var title: some View {
        if order.isBundle {
            Text(l10n.format(.ordersBundleTitle, order.items.count))
                .taleedFont(TaleedFont.bodyLarge.with(weight: .semibold))
                .foregroundStyle(TaleedColor.textPrimary)
        } else {
            Button { openListing(order.items.first?.listingId) } label: {
                Text(verbatim: order.title.isolatedByContent)
                    .taleedFont(TaleedFont.bodyLarge.with(weight: .semibold))
                    .foregroundStyle(TaleedColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("order.listing")
        }
    }

    private var amount: some View {
        PriceText(amount: OrderRules.headlineAmount(for: order), style: TaleedFont.buttonMedium)
    }

    /// "Vendeur" and the avatar and handle (opens the profile), or "Compte supprimé". From accessibility
    /// text sizes on, the role sits above the avatar and handle.
    @ViewBuilder
    private var counterpart: some View {
        let role = l10n.string(order.side == .seller ? .ordersBuyer : .ordersSeller)
        if let member = order.counterpart {
            Button {
                if let username = member.username { router.push(.member(username: username)) }
            } label: {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                            roleText(role)
                            memberLine(member)
                        }
                    } else {
                        HStack(spacing: TaleedSpacing.s8) {
                            avatar(member)
                            roleText(role)
                                .fixedSize()
                            handle(member)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: TaleedSize.touchTargetMin, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(member.username == nil)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("order.counterpart")
        } else {
            HStack(spacing: TaleedSpacing.s8) {
                TaleedAvatar(initials: "", size: 24)
                roleText(role)
                Text(l10n.string(.ordersDeletedAccount))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func roleText(_ role: String) -> some View {
        Text(role)
            .taleedFont(TaleedFont.caption)
            .foregroundStyle(TaleedColor.textSecondarySmall)
    }

    private func avatar(_ member: MemberRef) -> some View {
        TaleedAvatar(initials: TaleedAvatar.initials(from: member.username ?? member.displayName), size: 24,
                     imageURL: member.avatarURL)
    }

    private func memberLine(_ member: MemberRef) -> some View {
        HStack(spacing: TaleedSpacing.s8) {
            avatar(member)
            handle(member)
        }
    }

    /// The handle, then the official or verified mark.
    @ViewBuilder
    private func handle(_ member: MemberRef) -> some View {
        Text(verbatim: member.displayName.isolatedLeftToRight)
            .taleedFont(TaleedFont.bodyRegular)
            .foregroundStyle(TaleedColor.textPrimary)
            .lineLimit(1)
        if member.isOfficial {
            TaleedIconView(.sealCheck, size: 14, color: TaleedColor.brandPrimary)
                .accessibilityLabel(l10n.string(.profileOfficial))
        } else if member.isVerified {
            TaleedIconView(.shieldCheck, size: 14, color: TaleedColor.feedbackSuccess)
                .accessibilityLabel(l10n.string(.profileVerified))
        }
    }

    private func openListing(_ listingId: String?) {
        if let listingId { router.push(.listing(id: listingId)) }
    }
}

/// "Livraison" or "Retrait au stop-desk": the recipient, the phone, the desk or the address, the
/// commune and wilaya, and the tracking number once the parcel exists.
struct OrderDeliveryCard: View {
    let delivery: OrderDeliveryInfo
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                HStack(spacing: TaleedSpacing.s8) {
                    TaleedIconView(delivery.kind == .stopdesk ? .storefront : .house, size: 20, color: TaleedColor.textSecondary)
                        .accessibilityHidden(true)
                    Text(l10n.string(delivery.kind == .stopdesk ? .ordersStopdeskPickup : .ordersDeliveryTo))
                        .taleedFont(TaleedFont.headline)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.bottom, TaleedSpacing.s4)
                Text(verbatim: delivery.recipientName)
                    .taleedFont(TaleedFont.bodyRegular.with(weight: .semibold))
                    .foregroundStyle(TaleedColor.textPrimary)
                Text(verbatim: delivery.phone.isolatedLeftToRight)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                if let desk = delivery.stopdeskName {
                    Text(verbatim: desk).taleedFont(TaleedFont.bodyRegular).foregroundStyle(TaleedColor.textBody)
                }
                if let address = delivery.addressLine {
                    Text(verbatim: address).taleedFont(TaleedFont.bodyRegular).foregroundStyle(TaleedColor.textBody)
                }
                Text(verbatim: "\(delivery.commune), \(delivery.wilaya)")
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
            }
            .padding(TaleedSpacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let tracking = delivery.tracking {
                HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s12) {
                    Text(l10n.string(.ordersTracking))
                        .taleedFont(TaleedFont.caption)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                    Spacer(minLength: 0)
                    Text(verbatim: tracking)
                        .font(.system(.footnote, design: .monospaced).weight(.medium))
                        .foregroundStyle(TaleedColor.textPrimary)
                        .textSelection(.enabled)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("order.tracking")
                }
                .padding(.horizontal, TaleedSpacing.s16)
                .padding(.vertical, TaleedSpacing.s12)
                .background(TaleedColor.surfaceGrouped)
                .accessibilityElement(children: .combine)
            }
        }
        .taleedCard()
        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
    }
}
