import SwiftUI

/// "Vos filleuls" (website `referrals-dialog.tsx`; a full-height bottom sheet on the phone): the members
/// invited, newest first and paged, each with "Inscrit le …" and its two reward badges (done, still
/// possible until the deadline, or missed); none yet: the gift, the hero title, "Pas encore de filleul…"
/// and the invite buttons. Then, once the member has vouchers, "Vos bons d’achat" (`ACTIVE` first, used and
/// expired ones greyed; a used one opens its order). Pull-to-refresh reloads both.
struct ReferralsSheet: View {
    let model: ReferralsViewModel
    let copy: ReferralsCopy
    /// Opens a screen once the sheet is gone (a member's profile, the order a voucher paid for).
    let onOpen: (AppRoute) -> Void
    let onClose: () -> Void
    /// The height the sheet needs while it holds only the empty state (`model.isSheetCompact`).
    var onCompactHeight: (CGFloat) -> Void = { _ in }
    @State private var toasts = TaleedToastState()
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        Group {
            if model.isSheetCompact {
                compactBody
            } else {
                listBody
            }
        }
        .taleedToastHost(toasts)
        .onChange(of: model.referrals.refreshError) { _, error in
            if let error { toasts.show(ToastItem(kind: .error, message: l10n.message(for: error))) }
        }
    }

    /// No member yet and no voucher: the empty state alone, measured so the sheet fits it (it scrolls
    /// when large text makes it taller than the screen).
    private var compactBody: some View {
        ScrollView {
            TaleedBottomSheet(title: l10n.string(.referralsYourReferrals), onClose: onClose) {
                emptyState
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onCompactHeight($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await model.refresh() }
        .accessibilityIdentifier("referrals.sheet")
    }

    private var listBody: some View {
        TaleedBottomSheet(title: l10n.string(.referralsYourReferrals), onClose: onClose) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    referralsList
                    if model.showsVouchers { vouchersSection }
                    vouchersFailure
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("referrals.sheet")
        }
        .padding(.bottom, -TaleedSize.bottomSheetPaddingBottom)
    }

    // MARK: Members invited

    @ViewBuilder
    private var referralsList: some View {
        let list = model.referrals
        if list.isEmpty {
            emptyState
        } else {
            ForEach(list.items) { row in
                ReferralRowView(row: row, copy: copy) {
                    if let username = row.member.username { onOpen(.member(username: username)) }
                }
            }
            PaginationFooter(list: list)
        }
    }

    /// The website's empty dialog: the gift, the hero title, then the copy and share buttons; plus the
    /// website's unused `referralsEmpty` line (screens.md §7 G18 lets the app use it).
    private var emptyState: some View {
        VStack(spacing: TaleedSpacing.s16) {
            TaleedIconView(.gift, size: 28, color: TaleedColor.brandPrimary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(TaleedColor.brandSoft))
                .accessibilityHidden(true)
            VStack(spacing: TaleedSpacing.s8) {
                Text(copy.heroTitle)
                    .taleedFont(TaleedFont.bodyLarge.with(weight: .semibold))
                    .foregroundStyle(TaleedColor.textPrimary)
                Text(l10n.string(.referralsReferralsEmpty))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            if case let .invite(url) = copy.program.access {
                CopyInviteButton(isCopied: model.isCopied) {
                    model.copyInvite()
                    // The screen's toasts show under the sheet: the sheet's own.
                    toasts.show(ToastItem(kind: .success, message: l10n.string(.referralsCopied)))
                }
                ShareInviteButton(url: url)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TaleedSpacing.s24)
        .accessibilityIdentifier("referrals.empty")
    }

    // MARK: Vouchers

    private var vouchersSection: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            Eyebrow(text: l10n.string(.referralsYourVouchers))
                .padding(.top, TaleedSpacing.s24)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.vouchers.items) { voucher in
                VoucherCard(voucher: voucher, copy: copy) {
                    if let orderId = voucher.openableOrderId { onOpen(.order(id: orderId)) }
                }
            }
            PaginationFooter(list: model.vouchers)
        }
        .accessibilityIdentifier("referrals.vouchers")
    }

    /// The vouchers could not load: say so under the members, with Retry (the members still show).
    @ViewBuilder
    private var vouchersFailure: some View {
        if copy.program.canRefer, !model.vouchers.hasLoaded, let error = model.vouchers.error {
            VStack(spacing: TaleedSpacing.s8) {
                Text(l10n.message(for: error))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                    .multilineTextAlignment(.center)
                TaleedButton(title: l10n.string(.commonRetry), kind: .tertiary, size: .medium) {
                    Task { await model.retryVouchers() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, TaleedSpacing.s24)
        }
    }
}

// MARK: - Rows

/// A member invited: avatar, name, "Inscrit le …", the two reward badges with their deadline line, and a
/// chevron when the row opens the member's profile (as the voucher cards and the wallet lines).
private struct ReferralRowView: View {
    let row: ReferralRow
    let copy: ReferralsCopy
    let onOpen: () -> Void

    var body: some View {
        let listings = copy.listings(row)
        let sale = copy.sale(row)
        VStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: TaleedSpacing.s12) {
                    TaleedAvatar(initials: TaleedAvatar.initials(from: row.member.displayName), size: TaleedSize.avatarMd,
                                 imageURL: row.member.avatarURL, isVerified: row.member.isVerified || row.member.isOfficial)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                        Text(verbatim: row.member.displayName.isolatedByContent)
                            .taleedFont(TaleedFont.bodyRegular.with(weight: .semibold))
                            .foregroundStyle(TaleedColor.textPrimary)
                            .lineLimit(1)
                        Text(copy.joined(row))
                            .taleedFont(TaleedFont.bodySmall)
                            .foregroundStyle(TaleedColor.textSecondarySmall)
                        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                            MilestoneBadge(text: listings)
                            MilestoneBadge(text: sale)
                        }
                        .padding(.top, TaleedSpacing.s4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if row.member.username != nil {
                        TaleedIconView(.caretRight, size: 16, color: TaleedColor.textSecondary)
                            .frame(minHeight: TaleedSize.avatarMd)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, TaleedSpacing.s12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(row.member.username == nil)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("referrals.row.\(row.id)")
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
        }
    }
}

/// A reward: green when done (its text carries the ✓, so no second check icon), brand while still possible
/// ("Jusqu’au …"), grey when missed ("Délai dépassé"). Never colour alone: the text and the line under it
/// say it.
private struct MilestoneBadge: View {
    let text: MilestoneText

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TaleedBadge(title: text.title, tone: tone)
            if let caption = text.caption {
                Text(caption)
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(text.milestone == .missed ? TaleedColor.feedbackError : TaleedColor.textSecondarySmall)
            }
        }
    }

    private var tone: TaleedTone {
        switch text.milestone {
        case .done: .success
        case .open: .brand
        case .missed: .neutral
        }
    }
}

/// A voucher: the ticket, the amount, why it was granted, the server's status line and, while active,
/// "Expire le …". Used and expired ones are greyed; a used one opens its order.
private struct VoucherCard: View {
    let voucher: VoucherRow
    let copy: ReferralsCopy
    let onOpen: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        if voucher.openableOrderId != nil {
            Button(action: onOpen) { card(showsChevron: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("referrals.voucher.\(voucher.id)")
        } else {
            card(showsChevron: false)
                .accessibilityIdentifier("referrals.voucher.\(voucher.id)")
        }
    }

    private func card(showsChevron: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
        return HStack(alignment: .top, spacing: TaleedSpacing.s12) {
            TaleedIconView(.ticket, size: 20, color: voucher.isGreyed ? TaleedColor.textSecondary : TaleedColor.brandPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: copy.amount(voucher.amount))
                    .taleedFont(TaleedFont.bodyLarge.with(weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(TaleedColor.textPrimary)
                Text(verbatim: voucher.label)
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(TaleedColor.textBody)
                Text(verbatim: voucher.statusLabel)
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                if let expiry = voucher.shownExpiry {
                    Text(l10n.format(.referralsVoucherExpires, copy.date(expiry)))
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                TaleedIconView(.caretRight, size: 16, color: TaleedColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(TaleedSpacing.s12)
        .frame(minHeight: TaleedSize.touchTargetMin)
        .background(voucher.isGreyed ? TaleedColor.surfaceGrouped : TaleedColor.brandSoft, in: shape)
        .overlay(shape.strokeBorder(voucher.isGreyed ? TaleedColor.borderSubtle : TaleedColor.brandPrimary.opacity(0.3)))
        .opacity(voucher.isGreyed ? 0.6 : 1)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}
