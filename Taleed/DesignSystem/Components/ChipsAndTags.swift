import SwiftUI

/// A 30 pt pill (chips, filter chips, badges, large condition tags). Grows with Dynamic Type.
private struct Pill<Content: View>: View {
    let fill: Color
    var border: Color?
    var height: CGFloat = TaleedSize.Chip.height
    var paddingX: CGFloat = TaleedSize.Chip.paddingX
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, paddingX)
            .padding(.vertical, 2)
            .frame(minHeight: height)
            .background(Capsule().fill(fill))
            .overlay {
                if let border { Capsule().strokeBorder(border, lineWidth: 1) }
            }
    }
}

/// Category chip (design-system §2.7): label then icon. Selected uses the "All" look
/// (`navy/800`, white label and icon).
struct CategoryChip: View {
    let title: String
    var icon: TaleedIcon?
    var iconSize: CGFloat = TaleedSize.Chip.iconSize
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Pill(fill: isSelected ? TaleedColor.navy800 : TaleedColor.blue50) {
                HStack(spacing: TaleedSize.Chip.gap) {
                    Text(title)
                        .taleedFont(TaleedFont.caption)
                        .foregroundStyle(isSelected ? TaleedColor.textInverse : TaleedColor.textBody)
                    if let icon {
                        TaleedIconView(icon, size: iconSize, color: isSelected ? TaleedColor.textInverse : TaleedColor.blue800)
                    }
                }
            }
            .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Tones shared by filter chips, removable filters and badges.
enum TaleedTone: String, CaseIterable, Sendable {
    /// `brandSoft` / `brandDark`.
    case brand
    /// `successSoft` / `feedback/success`.
    case success
    /// `warningSoft` / `warningText`.
    case warning
    /// `surfaceGrouped` / `textBody`.
    case neutral

    var fill: Color {
        switch self {
        case .brand: TaleedColor.brandSoft
        case .success: TaleedColor.successSoft
        case .warning: TaleedColor.warningSoft
        case .neutral: TaleedColor.surfaceGrouped
        }
    }

    var foreground: Color {
        switch self {
        case .brand: TaleedColor.brandDark
        case .success: TaleedColor.feedbackSuccess
        case .warning: TaleedColor.warningText
        case .neutral: TaleedColor.textBody
        }
    }

    /// Icon colour; the price-range chip tints its icon `brand/primary`.
    var icon: Color { self == .brand ? TaleedColor.brandPrimary : foreground }
}

/// Filter chip with a leading icon: location ("Oran", success tone, `map-pin`) or price range
/// ("Under 5,000 DA", brand tone, `sliders-horizontal`).
struct FilterChip: View {
    let title: String
    var icon: TaleedIcon = .mapPin
    var tone: TaleedTone = .success
    var action: (() -> Void)?

    var body: some View {
        let content = Pill(fill: tone.fill) {
            HStack(spacing: TaleedSpacing.s8) {
                TaleedIconView(icon, size: 14, color: tone.icon)
                Text(title)
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(tone.foreground)
            }
        }
        if let action {
            Button(action: action) { content.minimumHitArea() }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

/// Removable filter (design-system §2.7): label then ×; tapping removes the filter.
struct RemovableFilterChip: View {
    let title: String
    var tone: TaleedTone = .brand
    let onRemove: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onRemove) {
            Pill(fill: tone.fill) {
                HStack(spacing: TaleedSpacing.s4) {
                    Text(title)
                        .taleedFont(TaleedFont.caption)
                    TaleedIconView(.x, size: 12, color: nil)
                }
                .foregroundStyle(tone.foreground)
            }
            .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DesignSystemStrings.format(.a11yRemoveFilter, locale: locale, title))
    }
}

/// A row of chips that scrolls horizontally, with the screen margin on both sides.
struct ChipRow<Content: View>: View {
    var spacing: CGFloat = TaleedLayout.chipRowGap
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.vertical, 7)
        }
    }
}

/// Badge (design-system §2.8): "New" (brand), "Verified" with a shield (success), "Reserved" (warning).
struct TaleedBadge: View {
    let title: String
    var tone: TaleedTone = .brand
    var icon: TaleedIcon?

    var body: some View {
        Pill(fill: tone.fill) {
            HStack(spacing: TaleedSpacing.s4) {
                if let icon { TaleedIconView(icon, size: 14, color: tone.foreground) }
                Text(title).taleedFont(TaleedFont.tagLabel)
            }
            .foregroundStyle(tone.foreground)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Count badge: 24 circle in `feedback/error`, white 11/800 digits. Shows "99+" above 99.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: count > 99 ? "99+" : "\(count)")
            .taleedFont(TaleedFont.countBadge)
            .foregroundStyle(TaleedColor.textInverse)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .frame(minWidth: TaleedSize.countBadge, minHeight: TaleedSize.countBadge)
            .background(Capsule().fill(TaleedColor.feedbackError))
    }
}

/// Condition tag (design-system §2.9). Small (22 pt) on cards and photos; large (30 pt) in list
/// rows and detail. The label always shows (never colour alone).
struct ConditionTag: View {
    enum Size: Sendable { case small, large }

    let condition: ProductCondition?
    /// Shown for an unknown API code (the catalog's full label).
    var fallbackLabel: String = ""
    var size: Size = .small
    @Environment(\.locale) private var locale

    init(_ condition: ProductCondition, size: Size = .small) {
        self.condition = condition
        self.size = size
    }

    /// A tag from an API condition code; unknown codes show `fallbackLabel` in the neutral look.
    init(code: String, fallbackLabel: String, size: Size = .small) {
        self.condition = ProductCondition(code: code)
        self.fallbackLabel = fallbackLabel
        self.size = size
    }

    var body: some View {
        let tone = condition?.tone ?? .neutral
        Text(condition?.label(in: AppLanguage(locale: locale)) ?? fallbackLabel)
            .taleedFont(TaleedFont.tagLabel)
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .padding(.horizontal, size == .small ? TaleedSize.ConditionTag.paddingX : TaleedSize.Chip.paddingX)
            .padding(.vertical, size == .small ? TaleedSize.ConditionTag.paddingY : 2)
            .frame(minHeight: size == .small ? TaleedSize.ConditionTag.height : TaleedSize.Chip.height)
            .background(Capsule().fill(tone.fill))
    }
}

extension ProductCondition {
    /// Tag colours: New tagged = brand, Like new and Very good = success, Good = warning, Fair = neutral.
    var tone: TaleedTone {
        switch self {
        case .newWithTags: .brand
        case .newWithoutTags, .veryGood: .success
        case .good: .warning
        case .satisfactory: .neutral
        }
    }
}

/// Size tag on product cards: 19 pt outlined pill ("M", "38").
struct SizeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .taleedFont(TaleedFont.caption)
            .foregroundStyle(TaleedColor.textBody)
            .lineLimit(1)
            .padding(.horizontal, TaleedSize.SizeTag.paddingX)
            .padding(.vertical, 1)
            .frame(minHeight: TaleedSize.SizeTag.height)
            .overlay(Capsule().strokeBorder(TaleedColor.borderSubtle, lineWidth: TaleedSize.SizeTag.borderWidth))
    }
}

/// Equal-width tabs with a 3 pt indicator under the active one (design-system §2.10).
struct TaleedTabs: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                let isActive = index == selection
                Button {
                    selection = index
                } label: {
                    VStack(spacing: TaleedSpacing.s12) {
                        Text(title)
                            .taleedFont(TaleedFont.buttonMedium)
                            .foregroundStyle(isActive ? TaleedColor.brandPrimary : TaleedColor.textBody)
                            .multilineTextAlignment(.center)
                        Capsule()
                            .fill(isActive ? TaleedColor.brandPrimary : .clear)
                            .frame(height: 3)
                    }
                    .padding(.top, TaleedSpacing.s12)
                    .frame(maxWidth: .infinity, minHeight: TaleedSize.touchTargetMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1)
        }
        .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: selection)
    }
}

#Preview("Chips and tags") {
    VStack(alignment: .leading, spacing: 12) {
        ChipRow {
            CategoryChip(title: "All", isSelected: true) {}
            CategoryChip(title: "Kids", icon: .baby, iconSize: 18) {}
            CategoryChip(title: "Women", icon: .dress) {}
        }
        HStack {
            FilterChip(title: "Oran")
            FilterChip(title: "Under 5,000 DA", icon: .slidersHorizontal, tone: .brand)
        }
        HStack {
            ForEach(ProductCondition.allCases, id: \.self) { ConditionTag($0) }
        }
        HStack {
            TaleedBadge(title: "Verified", tone: .success, icon: .shieldCheck)
            CountBadge(count: 3)
            SizeTag(text: "M")
        }
        TaleedTabs(titles: ["For you", "Nearby", "Following"], selection: .constant(0))
    }
}
