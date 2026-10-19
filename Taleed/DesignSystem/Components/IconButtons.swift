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
        let iconColor = !isEnabled ? TaleedColor.navy400 : isActive ? TaleedColor.brandPrimary : TaleedColor.textPrimary
        TaleedIconView(icon, size: TaleedSize.IconButton.iconSize, color: iconColor)
            .frame(width: TaleedSize.IconButton.size, height: TaleedSize.IconButton.size)
            .taleedCard(
                fill: isActive ? TaleedColor.brandSoft : TaleedColor.surfacePrimary,
                border: isActive ? TaleedColor.brandSoftBorder : TaleedColor.borderSubtle,
                radius: TaleedSize.IconButton.radius
            )
            .contentShape(Rectangle())
    }
}

/// The favorite control on product cards and Item Detail (design-system §2.3, decision D-7):
/// a small tertiary button with a heart and an optional count. Saved = filled heart in mint.
/// The caller updates `isSaved` and `count` at once (optimistic) and reverts on failure.
struct FavoriteControl: View {
    let isSaved: Bool
    var count: Int?
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            HStack(spacing: TaleedSize.FavoriteButton.gap) {
                TaleedIconView(
                    isSaved ? .heartFill : .heart,
                    size: TaleedSize.FavoriteButton.iconSize,
                    color: isSaved ? TaleedColor.brandAccent : TaleedColor.brandPrimary
                )
                if let count {
                    Text(verbatim: "\(count)")
                        .taleedFont(TaleedFont.buttonSmall)
                        .foregroundStyle(TaleedColor.blue600)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, TaleedSize.FavoriteButton.padding)
            .frame(minHeight: TaleedSize.FavoriteButton.height)
            .taleedCard(fill: TaleedColor.blue50, border: TaleedColor.blue100, radius: TaleedSize.FavoriteButton.radius)
            .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DesignSystemStrings.string(isSaved ? .a11yFavoriteRemove : .a11yFavoriteAdd, locale: locale))
        .accessibilityValue(count.map { "\($0)" } ?? "")
        .accessibilityAddTraits(isSaved ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSaved)
    }
}

/// The round favorite of product list rows (design-system §3.3): 40 circle, red heart when saved.
struct FavoriteCircleButton: View {
    let isSaved: Bool
    var diameter: CGFloat = 40
    /// False draws the heart alone (dense search rows: `#778198`, red when saved).
    var showsBackground = true
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            TaleedIconView(.heart, size: 18, color: isSaved ? TaleedColor.feedbackError
                : showsBackground ? TaleedColor.textPrimary : TaleedColor.textSecondary)
                .frame(width: diameter, height: diameter)
                .background {
                    if showsBackground { Circle().fill(isSaved ? TaleedColor.errorSoft : TaleedColor.surfaceGrouped) }
                }
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DesignSystemStrings.string(isSaved ? .a11yFavoriteRemove : .a11yFavoriteAdd, locale: locale))
        .accessibilityAddTraits(isSaved ? .isSelected : [])
    }
}

#Preview("Icon buttons") {
    HStack(spacing: 12) {
        TaleedIconButton(icon: .heart, accessibilityLabel: "Save") {}
        TaleedIconButton(icon: .heart, accessibilityLabel: "Save", isActive: true, activeIcon: .heartStraight) {}
        TaleedIconButton(icon: .dotsThree, accessibilityLabel: "More") {}.disabled(true)
        FavoriteControl(isSaved: true, count: 2) {}
        FavoriteControl(isSaved: false) {}
        FavoriteCircleButton(isSaved: true) {}
    }
    .padding()
}
