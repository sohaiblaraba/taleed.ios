import SwiftUI

/// Seller card (design-system §3.4, Figma 8:14204, "Trust before transaction"): avatar 56 with the
/// verified dot, the name, the reputation, then the three stats and "View profile" (an Outline Large
/// button). The member profile builds its header on it (decision D-12): an optional presence line
/// (online or last seen), a trailing tag (verified or official), its own details between the
/// identity and the stats, and its own actions in place of "View profile".
///
/// The stats keep three columns while they fit; with large text, one row per stat (value, then label),
/// so that no label breaks mid-word.
struct SellerCard<Details: View, Actions: View>: View {
    typealias Stat = SellerCardStat
    typealias Reputation = SellerCardReputation
    typealias Presence = SellerCardPresence
    typealias Tag = SellerCardTag

    let name: String
    let reputation: Reputation
    var initials: String?
    var imageURL: URL?
    /// The verified dot on the avatar.
    var isVerified = false
    /// The verified badge under the reputation (shown only when `isVerified`).
    var verifiedLabel: String?
    var presence: Presence?
    /// A tag at the trailing end of the identity row.
    var tag: Tag?
    var stats: [Stat] = []
    @ViewBuilder let details: Details
    @ViewBuilder let actions: Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static var gap: CGFloat { 18 }
    static var avatarSize: CGFloat { 56 }

    private static var nameStyle: TaleedTextStyle {
        TaleedTextStyle(size: 18, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .body)
    }

    private static var reputationStyle: TaleedTextStyle {
        TaleedTextStyle(size: 13, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .footnote)
    }

    private static var statValueStyle: TaleedTextStyle {
        TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .subheadline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            identity
            details
            if !stats.isEmpty { statsStrip }
            actions
        }
    }

    // MARK: Identity

    private var identity: some View {
        HStack(alignment: .top, spacing: 14) {
            TaleedAvatar(initials: initials ?? TaleedAvatar.initials(from: name), size: Self.avatarSize, imageURL: imageURL,
                         isVerified: isVerified)
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Text(verbatim: name.isolatedByContent)
                    .taleedFont(Self.nameStyle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                reputationRow
                if let presence { presenceRow(presence) }
                if isVerified, let verifiedLabel {
                    TaleedBadge(title: verifiedLabel, tone: .success, icon: .shieldCheck)
                }
                // From accessibility sizes on, the tag goes under the text, so the name keeps the width.
                if let tag, tagIsStacked { tagBadge(tag) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let tag, !tagIsStacked { tagBadge(tag) }
        }
    }

    private var tagIsStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    private func tagBadge(_ tag: Tag) -> some View {
        TaleedBadge(title: tag.title, tone: tag.tone, icon: tag.icon)
    }

    private var reputationRow: some View {
        HStack(spacing: TaleedSpacing.s4) {
            if reputation.showsStar {
                TaleedIconView(.star, size: 14, color: TaleedColor.feedbackWarning)
            }
            Text(verbatim: reputation.text)
                .taleedFont(Self.reputationStyle)
                .foregroundStyle(TaleedColor.textBody)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reputation.accessibilityLabel ?? reputation.text)
        .accessibilityHint(reputation.accessibilityHint ?? "")
    }

    @ViewBuilder
    private func presenceRow(_ presence: Presence) -> some View {
        switch presence {
        case let .online(text):
            HStack(spacing: 6) {
                Circle().fill(TaleedColor.feedbackSuccess).frame(width: 6, height: 6).accessibilityHidden(true)
                presenceText(text)
            }
        case let .lastSeen(text):
            presenceText(text)
        }
    }

    private func presenceText(_ text: String) -> some View {
        Text(verbatim: text)
            .taleedFont(TaleedFont.caption)
            .foregroundStyle(TaleedColor.textSecondarySmall)
    }

    // MARK: Stats

    private var statsStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TaleedSpacing.s8) {
                ForEach(stats) { stat in
                    VStack(spacing: TaleedSpacing.s4) {
                        statValue(stat.value)
                        statLabel(stat.label)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(stat.accessibilityLabel ?? "\(stat.value) \(stat.label)")
                }
            }
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                ForEach(stats) { stat in
                    HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
                        statValue(stat.value)
                        statLabel(stat.label)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(stat.accessibilityLabel ?? "\(stat.value) \(stat.label)")
                }
            }
        }
        .padding(TaleedSpacing.s16)
        .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .accessibilityIdentifier("sellerCard.stats")
    }

    private func statValue(_ value: String) -> some View {
        Text(verbatim: value)
            .taleedFont(Self.statValueStyle)
            .foregroundStyle(TaleedColor.textPrimary)
            .monospacedDigit()
    }

    private func statLabel(_ label: String) -> some View {
        // One word per label: never broken mid-word (the rows take over first).
        Text(verbatim: label)
            .taleedFont(TaleedFont.meta)
            .foregroundStyle(TaleedColor.textSecondarySmall)
            .lineLimit(1)
            .fixedSize()
    }
}

/// A stat of the seller card's strip.
struct SellerCardStat: Identifiable {
    let value: String
    let label: String
    /// What VoiceOver reads for the stat ("38 ventes"); "value label" when nil.
    var accessibilityLabel: String?
    var id: String { label }
}

/// The seller card's reputation line.
struct SellerCardReputation {
    let text: String
    /// A star before the text, for a rating ("★ 5.0 · 1").
    var showsStar = false
    var accessibilityLabel: String?
    var accessibilityHint: String?
}

/// The seller card's presence line.
enum SellerCardPresence: Equatable {
    /// "En ligne": the success dot before the text.
    case online(String)
    /// "Vu il y a 2 h".
    case lastSeen(String)
}

/// The tag at the trailing end of the seller card's identity row.
struct SellerCardTag {
    let title: String
    let tone: TaleedTone
    let icon: TaleedIcon?
}

/// The card's own action: "View profile", an Outline Large button.
struct SellerCardViewProfileButton: View {
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        TaleedButton(title: DesignSystemStrings.string(.sellerViewProfile, locale: locale), kind: .outline, size: .large,
                     isFullWidth: true, action: action)
    }
}

extension SellerCard where Details == EmptyView, Actions == SellerCardViewProfileButton {
    /// The design-system card: identity, stats and "View profile".
    init(name: String, reputation: String, initials: String? = nil, imageURL: URL? = nil, isVerified: Bool = false,
         verifiedLabel: String? = nil, stats: [Stat] = [], onViewProfile: @escaping () -> Void) {
        self.init(name: name, reputation: Reputation(text: reputation), initials: initials, imageURL: imageURL,
                  isVerified: isVerified, verifiedLabel: verifiedLabel, stats: stats,
                  details: { EmptyView() }, actions: { SellerCardViewProfileButton(action: onViewProfile) })
    }
}
