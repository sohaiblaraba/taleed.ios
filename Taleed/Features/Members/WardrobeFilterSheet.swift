import SwiftUI

/// The wardrobe filter (screens.md §7 G5, the website's `WardrobeFilters`), in the design-system sort
/// sheet (§5.3): the category, only when the member sells in more than one, then the sort; nothing
/// changes until "Voir les # résultats", which counts the chosen category's items.
struct WardrobeFilterSheet: View {
    let categories: [WardrobeCategory]
    let total: Int
    let onApply: (WardrobeQuery) -> Void
    let onClose: () -> Void
    @State private var draft: WardrobeQuery
    @Environment(LanguageManager.self) private var l10n

    init(query: WardrobeQuery, categories: [WardrobeCategory], total: Int,
         onApply: @escaping (WardrobeQuery) -> Void, onClose: @escaping () -> Void) {
        self.categories = categories
        self.total = total
        self.onApply = onApply
        self.onClose = onClose
        _draft = State(initialValue: query)
    }

    var body: some View {
        TaleedBottomSheet(title: l10n.string(.memberFilter), onClose: onClose) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                if WardrobeFilterRules.showsCategoryPicker(categories) {
                    group(title: l10n.string(.memberCategory)) {
                        option(l10n.string(.memberAllCategories), count: total, isSelected: draft.category == nil) {
                            draft.category = nil
                        }
                        ForEach(WardrobeFilterRules.sorted(categories, locale: l10n.language.locale)) { category in
                            option(WardrobeFilterRules.label(for: category, among: categories), count: category.count,
                                   isSelected: draft.category == category.slug) {
                                draft.category = category.slug
                            }
                        }
                    }
                }
                group(title: l10n.string(.filtersSort)) {
                    ForEach(WardrobeQuery.Sort.allCases, id: \.self) { sort in
                        option(l10n.string(Self.label(sort)), count: nil, isSelected: draft.sort == sort) {
                            draft.sort = sort
                        }
                    }
                }
            }
            let count = WardrobeFilterRules.count(for: draft.category, total: total, categories: categories)
            TaleedButton(title: l10n.format(.memberShowResults, count), kind: .primary, size: .large, isFullWidth: true) {
                onApply(draft)
            }
            .accessibilityIdentifier("member.filter.apply")
        }
    }

    static func label(_ sort: WardrobeQuery.Sort) -> L10nKey {
        switch sort {
        case .newest: .filtersSortNewest
        case .priceAsc: .filtersSortPriceAsc
        case .priceDesc: .filtersSortPriceDesc
        }
    }

    private func group(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(text: title)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func option(_ title: String, count: Int?, isSelected: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: TaleedSpacing.s8) {
                Text(title)
                    .taleedFont(isSelected ? TaleedFont.bodyLarge.with(weight: .semibold) : TaleedFont.bodyLarge)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count {
                    Text(verbatim: "\(count)")
                        .taleedFont(TaleedFont.caption)
                        .foregroundStyle(TaleedColor.textSecondary)
                        .monospacedDigit()
                }
                RadioIndicator(isSelected: isSelected)
            }
            .frame(minHeight: TaleedSize.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(title), \(l10n.format(.memberItemsCount, $0))" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
