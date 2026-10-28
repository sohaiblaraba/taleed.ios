import NukeUI
import SwiftUI

/// Circle avatar with initials or a photo, and an optional verified badge (design-system §2.11).
struct TaleedAvatar: View {
    /// The two looks in Figma: the design-system one and the one the wireframes draw (§8.18), as
    /// Android's `AvatarStyle`.
    enum Style: Sendable {
        /// `brandSoft` fill, `brandDark` SemiBold initials.
        case soft
        /// `blue/100` fill, `blue/700` Bold initials (app bar, Item Detail seller).
        case wireframe
    }

    let initials: String
    var size: CGFloat = 40
    var imageURL: URL?
    var isVerified = false
    var style: Style = .soft

    var body: some View {
        Circle()
            .fill(style == .soft ? TaleedColor.brandSoft : TaleedColor.brandTintStrong)
            .overlay {
                Text(verbatim: initials)
                    // Fixed size (the circle does not grow with Dynamic Type), with the brand cascade so
                    // Arabic initials render in Alexandria.
                    .font(Font(initialsStyle.uiFont()))
                    .foregroundStyle(style == .soft ? TaleedColor.brandDark : TaleedColor.brandOnTint)
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

    private var initialsStyle: TaleedTextStyle {
        TaleedTextStyle(size: Self.initialsSize(for: size), weight: style == .soft ? .semibold : .bold,
                        lineHeight: nil, letterSpacing: 0, relativeTo: .body)
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

    /// Initials for an avatar, the same rule as Android's `avatarInitials`: the first letters of the
    /// first two words of the display name, words split at spaces, "." and "_" after a leading "@"
    /// ("Lina N." → "LN", "@amina_b" → "AB"), "?" when there are none. Pass the member's `displayName`.
    nonisolated static func initials(from name: String) -> String {
        let handle = name.hasPrefix("@") ? String(name.dropFirst()) : name
        let words = handle.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" })
            .filter { !$0.allSatisfy(\.isWhitespace) }
        let initials = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
        return initials.isEmpty ? "?" : initials
    }
}

/// The 14 pt mint verified dot with a 2 pt white ring.
struct VerifiedDot: View {
    var body: some View {
        Circle()
            .fill(TaleedColor.brandAccent)
            .frame(width: TaleedSize.avatarVerifiedBadge, height: TaleedSize.avatarVerifiedBadge)
            .overlay(Circle().strokeBorder(TaleedColor.surfacePrimary, lineWidth: TaleedSize.avatarVerifiedBadgeBorder))
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
