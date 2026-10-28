import SwiftUI

/// 44 x 44 icon button with a border (design-system §2.2). `isActive` draws the soft-brand look
/// (for example a saved state). Disabled greys the icon.
struct TaleedIconButton: View {
    let icon: TaleedIcon
    let accessibilityLabel: String
    var isActive = false
    /// Icon drawn when active (the specimen swaps Heart for HeartStraight).
    var activeIcon: TaleedIcon?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconButtonFace(icon: isActive ? (activeIcon ?? icon) : icon, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct IconButtonFace: View {
    let icon: TaleedIcon
    let isActive: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let iconColor = !isEnabled ? TaleedColor.iconDisabled : isActive ? TaleedColor.brandPrimary : TaleedColor.textPrimary
        TaleedIconView(icon, size: TaleedSize.iconButtonIconSize, color: iconColor)
            .frame(width: TaleedSize.iconButtonSize, height: TaleedSize.iconButtonSize)
            .taleedCard(
                fill: isActive ? TaleedColor.brandSoft : TaleedColor.surfacePrimary,
                border: isActive ? TaleedColor.brandSoftBorder : TaleedColor.borderSubtle,
                radius: TaleedSize.iconButtonRadius
            )
            .contentShape(Rectangle())
    }
}

/// The favorite control on product cards and Item Detail (design-system §2.3, decision D-7): a
/// Tertiary Small button with a heart and an optional count. Saved = filled heart in mint; pressed
/// fills `blue/100`. The caller updates `isFavorite` and `count` at once (optimistic) and reverts on
/// failure. 32 pt high, 44 pt hit area. Android: `FavoriteButton(isFavorite, onToggle, count)`.
struct FavoriteButton: View {
    let isFavorite: Bool
    var count: Int?
    let onToggle: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: TaleedSize.favoriteButtonGap) {
                TaleedIconView(
                    isFavorite ? .heartFill : .heart,
                    size: TaleedSize.favoriteButtonIconSize,
                    color: isFavorite ? TaleedColor.brandAccent : TaleedColor.brandPrimary
                )
                if let count {
                    Text(verbatim: "\(count)")
                        .taleedFont(TaleedFont.buttonSmall)
                        .foregroundStyle(TaleedColor.brandEmphasis)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, TaleedSize.favoriteButtonPadding)
            .frame(minWidth: 36, minHeight: TaleedSize.favoriteButtonHeight)
        }
        .buttonStyle(FavoriteButtonStyle())
        .favoriteSemantics(isFavorite: isFavorite, count: count, locale: locale)
    }
}

/// `blue/50` with a `blue/100` border; `blue/100` while pressed (Tertiary).
private struct FavoriteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .taleedCard(fill: configuration.isPressed ? TaleedColor.brandTintStrong : TaleedColor.brandTint,
                        border: TaleedColor.brandTintBorder, radius: TaleedSize.favoriteButtonRadius)
            .contentShape(Rectangle())
            .minimumHitArea()
    }
}

/// The list-row favorite (design-system §3.3): a 40 circle, grouped fill with a navy heart, or
/// `errorSoft` with a filled red heart when saved (never colour alone). 44 pt hit area.
struct FavoriteCircleButton: View {
    let isFavorite: Bool
    let onToggle: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onToggle) {
            TaleedIconView(isFavorite ? .heartFill : .heart, size: 18,
                           color: isFavorite ? TaleedColor.feedbackError : TaleedColor.textPrimary)
                .frame(width: TaleedSize.productListRowFavorite, height: TaleedSize.productListRowFavorite)
                .background(Circle().fill(isFavorite ? TaleedColor.errorSoft : TaleedColor.surfaceGrouped))
                .contentShape(Circle())
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .favoriteSemantics(isFavorite: isFavorite, count: nil, locale: locale)
    }
}

/// The bare heart of the dense search-results row (design-system §3.3): heart 18 `#778198`; filled in
/// the saved mint of the cards and the listing (`brand/accent`, decision D-7) when saved. 44 pt box.
struct FavoriteHeartToggle: View {
    let isFavorite: Bool
    let onToggle: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onToggle) {
            TaleedIconView(isFavorite ? .heartFill : .heart, size: 18,
                           color: isFavorite ? TaleedColor.brandAccent : TaleedColor.textSecondary)
                .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .favoriteSemantics(isFavorite: isFavorite, count: nil, locale: locale)
    }
}

private extension View {
    /// The favorite controls read as a toggle "Add to favorites", "In your favorites" when saved, and the
    /// count through the `favorite_count` plural ("7 favorites"), like Android's checkbox semantics.
    func favoriteSemantics(isFavorite: Bool, count: Int?, locale: Locale) -> some View {
        let value = [
            isFavorite ? DesignSystemStrings.string(.favoriteSaved, locale: locale) : nil,
            count.map { DesignSystemStrings.format(.favoriteCount, locale: locale, $0) },
        ].compactMap { $0 }.joined(separator: ", ")
        return accessibilityLabel(DesignSystemStrings.string(.favoriteAdd, locale: locale))
            .accessibilityValue(value)
            .accessibilityAddTraits(isFavorite ? [.isToggle, .isSelected] : .isToggle)
            .sensoryFeedback(.selection, trigger: isFavorite)
    }
}

#Preview("Icon buttons") {
    HStack(spacing: 12) {
        TaleedIconButton(icon: .heart, accessibilityLabel: "Save") {}
        TaleedIconButton(icon: .heart, accessibilityLabel: "Save", isActive: true, activeIcon: .heartStraight) {}
        TaleedIconButton(icon: .dotsThree, accessibilityLabel: "More") {}.disabled(true)
        FavoriteButton(isFavorite: true, count: 2) {}
        FavoriteButton(isFavorite: false) {}
        FavoriteCircleButton(isFavorite: true) {}
        FavoriteHeartToggle(isFavorite: true) {}
    }
    .padding()
}
