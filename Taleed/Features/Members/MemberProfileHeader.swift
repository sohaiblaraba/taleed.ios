import SwiftUI

/// The top of a profile, the design-system `SellerCard` (§3.4, "Trust before transaction"): avatar 56
/// with the verified dot, the handle, the reputation ("★ 5.0 · 1"), online or last seen, and the
/// verified or official tag; then the bio, the wilaya and "Membre depuis",
/// the stats strip (sales, followers, following), the "Infos vérifiées" list, and the actions
/// (screens.md §2 G5 and §7 G5).
struct MemberProfileHeader: View {
    struct Handlers {
        let follow: () -> Void
        let unblock: () -> Void
        let editProfile: () -> Void
        let myListings: () -> Void
        let shopBundle: () -> Void
    }

    let profile: MemberProfile
    let actions: MemberProfileActions
    let isFollowRunning: Bool
    let isBlockRunning: Bool
    let handlers: Handlers
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        SellerCard(name: profile.displayName, reputation: reputation,
                   initials: TaleedAvatar.initials(from: profile.username), imageURL: profile.avatarURL,
                   isVerified: profile.isVerified && !profile.isOfficial, presence: presence, tag: tag,
                   stats: stats) {
            details
        } actions: {
            checks
            if actions.showsBlockedNotice {
                InlineAlert(kind: .warning, title: l10n.format(.appProfileBlockedNotice, profile.displayName.isolatedLeftToRight),
                            message: l10n.string(.appProfileBlockedNoticeBody))
                    .accessibilityIdentifier("member.blockedNotice")
            }
            primaryActions
            if actions.showsShopBundle { bundleBanner }
        }
        .padding(TaleedLayout.screenMargin)
    }

    // MARK: Identity

    /// "★ 5.0 · 1", the seller card's reputation; no stars before the first review (the website).
    private var reputation: SellerCardReputation {
        let sales = l10n.format(.memberSales, profile.salesCount)
        guard let rating = profile.rating else {
            return .init(text: l10n.string(.reviewsNoReviews), accessibilityHint: sales)
        }
        let average = RatingText.average(rating.average)
        return .init(text: "\(average) · \(rating.count)".isolatedLeftToRight, showsStar: true,
                     accessibilityLabel: l10n.format(.listingSellerRating, average, "\(rating.count)"),
                     accessibilityHint: sales)
    }

    private var presence: SellerCardPresence? {
        if profile.isOnline { return .online(l10n.string(.listingOnlineNow)) }
        guard let lastSeen = profile.lastSeenAt else { return nil }
        return .lastSeen(l10n.format(.listingLastSeen, RelativeTimeText.string(for: lastSeen, locale: l10n.language.formattingLocale)))
    }

    /// The official badge replaces the verified one (screens.md §0.3).
    private var tag: SellerCardTag? {
        if profile.isOfficial { return .init(title: l10n.string(.profileOfficial), tone: .brand, icon: .sealCheck) }
        if profile.isVerified { return .init(title: l10n.string(.profileVerified), tone: .success, icon: .shieldCheck) }
        return nil
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            if let bio = profile.bio {
                // Member-written: never translated, laid out by its own script.
                Text(verbatim: bio)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .naturalDirection(of: bio)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TaleedSpacing.s12) { metaItems }
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) { metaItems }
            }
        }
    }

    @ViewBuilder
    private var metaItems: some View {
        if let wilaya = profile.wilaya {
            metaItem(icon: .mapPin, text: wilaya.name)
        }
        let since = MemberProfileText.memberSince(profile.memberSince, locale: l10n.language.formattingLocale)
        metaItem(icon: .clock, text: l10n.format(.memberMemberSince, since))
    }

    private func metaItem(icon: TaleedIcon, text: String) -> some View {
        HStack(spacing: TaleedSpacing.s4) {
            TaleedIconView(icon, size: 14, color: TaleedColor.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .taleedFont(TaleedFont.caption)
                .foregroundStyle(TaleedColor.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Stats

    /// The seller card's stats strip: sales, followers, following.
    private var stats: [SellerCardStat] {
        [
            .init(value: "\(profile.salesCount)", label: l10n.string(.appProfileStatSales),
                  accessibilityLabel: l10n.format(.memberSales, profile.salesCount)),
            .init(value: "\(profile.followersCount)", label: l10n.string(.appProfileStatFollowers),
                  accessibilityLabel: l10n.format(.memberFollowers, profile.followersCount)),
            .init(value: "\(profile.followingCount)", label: l10n.string(.appProfileStatFollowing),
                  accessibilityLabel: l10n.format(.memberFollowingCount, profile.followingCount)),
        ]
    }
}

// Verified information and the actions.
private extension MemberProfileHeader {
    // MARK: Verified information

    var checks: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            Text(l10n.string(.memberChecksTitle).uppercased(with: l10n.language.locale))
                .taleedFont(TaleedFont.eyebrow)
                .foregroundStyle(TaleedColor.textSecondary)
                .accessibilityLabel(l10n.string(.memberChecksTitle))
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TaleedSpacing.s16) { checkItems }
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) { checkItems }
            }
        }
    }

    @ViewBuilder
    private var checkItems: some View {
        check(.memberCheckEmail, icon: .envelope, isDone: profile.checks.email)
        check(.memberCheckPhone, icon: .phone, isDone: profile.checks.phone)
        check(.memberCheckIdentity, icon: .shieldCheck, isDone: profile.checks.identity)
    }

    /// A check with its state: ✓ in the success colour when verified, – greyed otherwise (the website).
    private func check(_ label: L10nKey, icon: TaleedIcon, isDone: Bool) -> some View {
        HStack(spacing: TaleedSpacing.s4) {
            if isDone {
                TaleedIconView(.check, size: 14, color: TaleedColor.feedbackSuccess)
            } else {
                Capsule().fill(TaleedColor.textSecondary).frame(width: 8, height: 1.5)
                    .frame(width: 14, height: 14)
            }
            TaleedIconView(icon, size: 14, color: isDone ? TaleedColor.textPrimary : TaleedColor.textSecondary)
            Text(l10n.string(label))
                .taleedFont(isDone ? TaleedFont.caption.with(weight: .semibold) : TaleedFont.caption)
                .foregroundStyle(isDone ? TaleedColor.textPrimary : TaleedColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(label))
        .accessibilityValue(l10n.string(isDone ? .profileVerified : .appA11yNotVerified))
    }

    // MARK: Actions

    @ViewBuilder
    private var primaryActions: some View {
        switch actions.primary {
        case let .follow(following):
            // "Suivre" in the commerce colour; "Suivi" in the quiet outline, as the website's button.
            TaleedButton(title: l10n.string(following ? .memberFollowing : .memberFollow),
                         kind: following ? .outline : .secondary, size: .large,
                         leadingIcon: following ? .check : .plus, isLoading: isFollowRunning, isFullWidth: true,
                         action: handlers.follow)
                .accessibilityAddTraits(following ? .isSelected : [])
                .accessibilityIdentifier("member.follow")
        case .unblock:
            TaleedButton(title: l10n.string(.appProfileUnblock), kind: .outline, size: .large, isLoading: isBlockRunning,
                         isFullWidth: true, action: handlers.unblock)
                .accessibilityIdentifier("member.unblock")
        case .ownProfile:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TaleedSpacing.s8) { ownButtons }
                VStack(spacing: TaleedSpacing.s8) { ownButtons }
            }
        }
    }

    @ViewBuilder
    private var ownButtons: some View {
        TaleedButton(title: l10n.string(.appProfileEdit), kind: .outline, size: .large, isFullWidth: true,
                     action: handlers.editProfile)
            .accessibilityIdentifier("member.editProfile")
        TaleedButton(title: l10n.string(.appProfileMyListings), kind: .outline, size: .large, isFullWidth: true,
                     action: handlers.myListings)
            .accessibilityIdentifier("member.myListings")
    }

    /// The website's "Achète en lot" banner over the wardrobe: title, why, "Créer un lot".
    private var bundleBanner: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            HStack(spacing: TaleedSpacing.s8) {
                TaleedIconView(.storefront, size: 20, color: TaleedColor.brandPrimary)
                    .accessibilityHidden(true)
                Text(l10n.string(.bundleBannerTitle))
                    .taleedFont(TaleedFont.sectionTitle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(l10n.string(.bundleBannerBody))
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textBody)
                .fixedSize(horizontal: false, vertical: true)
            TaleedButton(title: l10n.string(.bundleCreate), kind: .tertiary, size: .medium, action: handlers.shopBundle)
                .accessibilityIdentifier("member.shopBundle")
        }
        .padding(TaleedSpacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaleedColor.blue50, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
    }
}
