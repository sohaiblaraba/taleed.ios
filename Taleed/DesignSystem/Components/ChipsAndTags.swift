import SwiftUI

/// A 30 pt pill (chips, filter chips, badges, large condition tags). Grows with Dynamic Type.
private struct Pill<Content: View>: View {
    let fill: Color
    var border: Color?
    var height: CGFloat = TaleedSize.chipHeight
    var paddingX: CGFloat = TaleedSize.chipPaddingX
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
    var iconSize: CGFloat = TaleedSize.chipIconSize
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Pill(fill: isSelected ? TaleedColor.navy800 : TaleedColor.blue50) {
                HStack(spacing: TaleedSize.chipGap) {
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
    /// `errorSoft` / `feedback/error`: a refusal ("Refusé"), as the website's destructive badge.
    case error

    var fill: Color {
        switch self {
        case .brand: TaleedColor.brandSoft
        case .success: TaleedColor.successSoft
        case .warning: TaleedColor.warningSoft
        case .neutral: TaleedColor.surfaceGrouped
        case .error: TaleedColor.errorSoft
        }
    }

    var foreground: Color {
        switch self {
        case .brand: TaleedColor.brandDark
        case .success: TaleedColor.feedbackSuccess
        case .warning: TaleedColor.warningText
        case .neutral: TaleedColor.textBody
        case .error: TaleedColor.feedbackError
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
        .accessibilityLabel(DesignSystemStrings.format(.commonRemoveFilter, locale: locale, title))
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
/// `compact` is the small tag's 22 pt shape (padding 8 / 4), for a status inside a dense list row.
/// `isOnTint` keeps a brand badge visible on a `brandSoft` surface (a pinned offer, the member's own
/// offer card): a `brandSoftBorder` outline around the same fill.
struct TaleedBadge: View {
    enum Size: Sendable {
        case regular, compact
    }

    let title: String
    var tone: TaleedTone = .brand
    var icon: TaleedIcon?
    var size: Size = .regular
    var isOnTint = false
    /// The icon grows with the label (up to twice its size), so it does not shrink beside large text.
    @ScaledMetric(relativeTo: .caption) private var iconScale: CGFloat = 1

    var body: some View {
        let compact = size == .compact
        let iconSize: CGFloat = compact ? 12 : 14
        Pill(fill: tone.fill, border: isOnTint && tone == .brand ? TaleedColor.brandSoftBorder : nil,
             height: compact ? TaleedSize.conditionTagHeight : TaleedSize.chipHeight,
             paddingX: compact ? TaleedSize.conditionTagPaddingX : TaleedSize.chipPaddingX) {
            HStack(spacing: TaleedSpacing.s4) {
                if let icon { TaleedIconView(icon, size: iconSize * min(iconScale, 2), color: tone.foreground) }
                // One line at its own width: a badge never wraps into a tall circle with a broken word.
                Text(title)
                    .taleedFont(TaleedFont.tagLabel)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(tone.foreground)
        }
        .accessibilityElement(children: .combine)
    }
}

extension TaleedBadge {
    /// The one "Verified" look (design-system "Verified · available"): success tone with the shield,
    /// for the member's badge, the verified email and the settings' verification row.
    static func verified(_ title: String, size: Size = .regular) -> TaleedBadge {
        TaleedBadge(title: title, tone: .success, icon: .shieldCheck, size: size)
    }
}

/// Count badge: 24 circle in `feedback/error`, white 11/800 digits. Shows "99+" above 99 (or
/// "`maxCount`+"), left to right in every language (never "+99"). `accessibilityLabel` says what is
/// counted ("3 unread messages"), as Android's `contentDescription`. The small size (18) sits on a
/// 20–24 pt icon (bottom navigation, the bell).
struct CountBadge: View {
    enum Size: Sendable {
        case regular, small
    }

    let count: Int
    let accessibilityLabel: String
    var maxCount = 99
    var size: Size = .regular

    var body: some View {
        let diameter = size == .regular ? TaleedSize.countBadge : 18
        Text(verbatim: (count > maxCount ? "\(maxCount)+" : "\(count)").isolatedLeftToRight)
            .taleedFont(TaleedFont.countBadge)
            .foregroundStyle(TaleedColor.textInverse)
            .monospacedDigit()
            .lineLimit(1)
            // Its own width, whatever the parent offers: an overlay on the 20 pt tab icon would
            // otherwise cut "9+" down to "…" (G1).
            .fixedSize()
            .padding(.horizontal, size == .regular ? 6 : 4)
            .frame(minWidth: diameter, minHeight: diameter)
            .background(Capsule().fill(TaleedColor.feedbackError))
            .overlay {
                if size == .small { Capsule().strokeBorder(TaleedColor.surfacePrimary, lineWidth: 1.5) }
            }
            .environment(\.layoutDirection, .leftToRight)
            // The small badge sits on the corner of a fixed-size icon (the bell, a tab), so it keeps its
            // size; the regular one (list rows) grows a little with the text.
            .dynamicTypeSize(...(size == .small ? DynamicTypeSize.large : DynamicTypeSize.xxxLarge))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }
}

/// Condition tag (design-system §2.9). Small (22 pt, short label) on cards and photos; large
/// (30 pt, full label: "Very good condition") in list rows, search results and detail. The label
/// always shows (never colour alone).
struct ConditionTag: View {
    enum Size: Sendable {
        case small, large

        var labelLength: ProductCondition.LabelLength { self == .small ? .short : .full }
    }

    let code: String
    /// The catalog's `label` and `shortLabel` (`GET /catalog` conditions), shown for a code the app
    /// does not know.
    var catalogLabel: String = ""
    var catalogShortLabel: String?
    var size: Size = .small
    @Environment(\.locale) private var locale

    init(_ condition: ProductCondition, size: Size = .small) {
        self.code = condition.rawValue
        self.size = size
    }

    /// A tag from an API condition code; unknown codes show the catalog labels in the neutral look.
    init(code: String, catalogLabel: String, catalogShortLabel: String? = nil, size: Size = .small) {
        self.code = code
        self.catalogLabel = catalogLabel
        self.catalogShortLabel = catalogShortLabel
        self.size = size
    }

    var body: some View {
        let tone = ProductCondition(code: code)?.tone ?? .neutral
        let small = size == .small
        // "Condition always explicit": the label wraps between words and the tag grows; it is never
        // cut. When one word is still wider than the room, the label steps down in size (Android's
        // ConditionTag).
        WordFittingText(text: ProductCondition.label(code: code, catalogLabel: catalogLabel,
                                                     catalogShortLabel: catalogShortLabel, length: size.labelLength,
                                                     language: AppLanguage(locale: locale)),
                        style: TaleedFont.tagLabel, alignment: .center)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, small ? TaleedSize.conditionTagPaddingX : TaleedSize.chipPaddingX)
            .padding(.vertical, small ? TaleedSize.conditionTagPaddingY : 2)
            .frame(minHeight: small ? TaleedSize.conditionTagHeight : TaleedSize.chipHeight)
            .background(RoundedRectangle(cornerRadius: (small ? TaleedSize.conditionTagHeight : TaleedSize.chipHeight) / 2,
                                         style: .continuous).fill(tone.fill))
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

/// Boosted tag on product cards, under the condition tag: the small tag's shape in `brand/primary`
/// with a white `sparkle` and label (Figma draws none; the API asks to show the boost, screens.md §0.4).
struct BoostedTag: View {
    let title: String

    var body: some View {
        HStack(spacing: TaleedSpacing.s4) {
            TaleedIconView(.sparkle, size: 12, color: TaleedColor.textInverse)
            Text(title)
                .taleedFont(TaleedFont.tagLabel)
                .foregroundStyle(TaleedColor.textInverse)
                .lineLimit(1)
        }
        .padding(.horizontal, TaleedSize.conditionTagPaddingX)
        .padding(.vertical, TaleedSize.conditionTagPaddingY)
        .frame(minHeight: TaleedSize.conditionTagHeight)
        .background(Capsule().fill(TaleedColor.brandPrimary))
        .accessibilityElement(children: .combine)
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
            .padding(.horizontal, TaleedSize.sizeTagPaddingX)
            .padding(.vertical, 1)
            .frame(minHeight: TaleedSize.sizeTagHeight)
            .overlay(Capsule().strokeBorder(TaleedColor.borderSubtle, lineWidth: TaleedSize.sizeTagBorderWidth))
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
            CountBadge(count: 3, accessibilityLabel: "3 unread messages")
            SizeTag(text: "M")
        }
        TaleedTabs(titles: ["For you", "Nearby", "Following"], selection: .constant(0))
    }
}
