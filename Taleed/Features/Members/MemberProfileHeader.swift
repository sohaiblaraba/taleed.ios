import SwiftUI

/// The top of a profile, built on the Figma seller card (design-system §3.4, "Trust before
/// transaction"): avatar 56 with the verified dot, the handle, the reputation ("★ 5.0 · 1 vente"),
/// online or last seen, and the verified or official tag; then the bio, the wilaya and "Membre depuis",
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

    private static let nameStyle = TaleedTextStyle(size: 18, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .body)
    private static let reputationStyle = TaleedTextStyle(size: 13, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                         relativeTo: .footnote)
    private static let statValueStyle = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                        relativeTo: .subheadline)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            identity
            details
            stats
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

    private var identity: some View {
        HStack(alignment: .top, spacing: 14) {
            TaleedAvatar(initials: TaleedAvatar.initials(from: profile.username), size: 56, imageURL: profile.avatarURL,
                         isVerified: profile.isVerified && !profile.isOfficial)
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Text(verbatim: profile.displayName.isolatedLeftToRight)
                    .taleedFont(Self.nameStyle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                reputation
                presence
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            // The official badge replaces the verified one (screens.md §0.3).
            if profile.isOfficial {
                TaleedBadge(title: l10n.string(.profileOfficial), tone: .brand, icon: .sealCheck)
            } else if profile.isVerified {
                TaleedBadge(title: l10n.string(.profileVerified), tone: .success, icon: .shieldCheck)
            }
        }
    }

    /// "★ 5.0 · 1 vente", the seller card's reputation; no stars before the first review (the website).
    private var reputation: some View {
        let sales = l10n.format(.memberSales, profile.salesCount)
        return Group {
            if let rating = profile.rating {
                HStack(spacing: TaleedSpacing.s4) {
                    TaleedIconView(.star, size: 14, color: TaleedColor.warningIcon)
                    Text(verbatim: "\(RatingText.average(rating.average)) · \(rating.count)".isolatedLeftToRight)
                        .taleedFont(Self.reputationStyle)
                        .foregroundStyle(TaleedColor.textBody)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(l10n.format(.listingSellerRating, RatingText.average(rating.average), "\(rating.count)"))
            } else {
                Text(l10n.string(.reviewsNoReviews))
                    .taleedFont(Self.reputationStyle)
                    .foregroundStyle(TaleedColor.textBody)
            }
        }
        .accessibilityHint(sales)
    }

    @ViewBuilder
    private var presence: some View {
        if profile.isOnline {
            HStack(spacing: 6) {
                Circle().fill(TaleedColor.feedbackSuccess).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(l10n.string(.listingOnlineNow))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textSecondary)
            }
        } else if let lastSeen = profile.lastSeenAt {
            Text(l10n.format(.listingLastSeen, RelativeTimeText.string(for: lastSeen, locale: l10n.language.formattingLocale)))
                .taleedFont(TaleedFont.caption)
                .foregroundStyle(TaleedColor.textSecondary)
        }
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

    /// The seller card's stats strip: value over label, three columns; one row per stat when large text
    /// no longer fits three columns.
    private var stats: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TaleedSpacing.s8) {
                ForEach(statItems, id: \.label) { item in
                    VStack(spacing: TaleedSpacing.s4) {
                        statValue(item.value)
                        statLabel(item.label)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.spoken)
                }
            }
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                ForEach(statItems, id: \.label) { item in
                    HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
                        statValue(item.value)
                        statLabel(item.label)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.spoken)
                }
            }
        }
        .padding(TaleedSpacing.s16)
        .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .accessibilityIdentifier("member.stats")
    }

    private struct StatItem {
        let value: Int
        let label: L10nKey
        let spoken: String
    }

    private var statItems: [StatItem] {
        [
            StatItem(value: profile.salesCount, label: .appProfileStatSales, spoken: l10n.format(.memberSales, profile.salesCount)),
            StatItem(value: profile.followersCount, label: .appProfileStatFollowers,
                     spoken: l10n.format(.memberFollowers, profile.followersCount)),
            StatItem(value: profile.followingCount, label: .appProfileStatFollowing,
                     spoken: l10n.format(.memberFollowingCount, profile.followingCount)),
        ]
    }

    private func statValue(_ value: Int) -> some View {
        Text(verbatim: "\(value)")
            .taleedFont(Self.statValueStyle)
            .foregroundStyle(TaleedColor.textPrimary)
            .monospacedDigit()
    }

    private func statLabel(_ label: L10nKey) -> some View {
        // One word per label: never broken mid-word (the rows take over first).
        Text(l10n.string(label))
            .taleedFont(TaleedFont.meta)
            .foregroundStyle(TaleedColor.textSecondary)
            .lineLimit(1)
            .fixedSize()
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
