import NukeUI
import SwiftUI

/// Circle avatar with initials or a photo, and an optional verified badge (design-system §2.11).
struct TaleedAvatar: View {
    /// The two looks in Figma: the design-system one and the one the wireframes draw (§8.18).
    enum Style: Sendable {
        /// `brandSoft` fill, `brandDark` SemiBold initials.
        case standard
        /// `blue/100` fill, `blue/700` Bold initials (app bar, Item Detail seller).
        case wireframe
    }

    let initials: String
    var size: CGFloat = 40
    var imageURL: URL?
    var isVerified = false
    var style: Style = .standard

    var body: some View {
        Circle()
            .fill(style == .standard ? TaleedColor.brandSoft : TaleedColor.blue100)
            .overlay {
                Text(verbatim: initials)
                    .font(.custom(TaleedTypeface.plusJakartaSans.postScriptName(style == .standard ? .semibold : .bold),
                                  fixedSize: Self.initialsSize(for: size)))
                    .foregroundStyle(style == .standard ? TaleedColor.brandDark : TaleedColor.blue700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .overlay {
                if let imageURL {
                    LazyImage(url: imageURL) { state in
                        if let image = state.image { image.resizable().scaledToFill() }
                    }
                    .clipShape(Circle())
                }
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if isVerified { VerifiedDot().padding(.trailing, -2).padding(.bottom, -2) }
            }
            .accessibilityHidden(true)
    }

    /// Initials size by avatar size (32 → 11, 40 → 14, 48 → 16, 56 → 18, 72 → 24; wireframe 36 → 12, 44 → 16).
    nonisolated static func initialsSize(for size: CGFloat) -> CGFloat {
        switch size {
        case ..<34: 11
        case ..<38: 12
        case ..<42: 14
        case ..<52: 16
        case ..<64: 18
        default: 24
        }
    }

    /// Up to two initials from a display name: "Lina N." → "LN", "@saf" → "S".
    nonisolated static func initials(from name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).map { $0.filter { $0.isLetter || $0.isNumber } }
        return words.filter { !$0.isEmpty }.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

/// The 14 pt mint verified dot with a 2 pt white ring.
struct VerifiedDot: View {
    var body: some View {
        Circle()
            .fill(TaleedColor.brandAccent)
            .frame(width: TaleedSize.Avatar.verifiedBadge, height: TaleedSize.Avatar.verifiedBadge)
            .overlay(Circle().strokeBorder(TaleedColor.surfacePrimary, lineWidth: TaleedSize.Avatar.verifiedBadgeBorder))
    }
}

/// Seller row (design-system §2.11): grouped card with avatar, name, reputation and a chevron.
struct SellerRow: View {
    let name: String
    let reputation: String
    var initials: String?
    var imageURL: URL?
    var isVerified = false
    var verifiedLabel: String?
    let action: () -> Void

    private static let nameStyle = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                   relativeTo: .subheadline)

    var body: some View {
        Button(action: action) {
            HStack(spacing: TaleedSpacing.s12) {
                TaleedAvatar(initials: initials ?? TaleedAvatar.initials(from: name), size: 48, imageURL: imageURL,
                             isVerified: isVerified)
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                    Text(verbatim: name.isolatedByContent)
                        .taleedFont(Self.nameStyle)
                        .foregroundStyle(TaleedColor.textPrimary)
                    Text(reputation)
                        .taleedFont(TaleedFont.meta)
                        .foregroundStyle(TaleedColor.textBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TaleedIconView(.caretRight, size: 18, color: TaleedColor.textSecondary)
            }
            .padding(TaleedSpacing.s16)
            .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, isVerified ? verifiedLabel : nil, reputation].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Identity") {
    VStack(spacing: 16) {
        HStack {
            ForEach([32, 40, 48, 56, 72] as [CGFloat], id: \.self) { size in
                TaleedAvatar(initials: "LN", size: size, isVerified: size > 32 && size < 72)
            }
        }
        SellerRow(name: "Lina N.", reputation: "4.9 ★ · 38 sales · Algiers", isVerified: true) {}
    }
    .padding()
}
