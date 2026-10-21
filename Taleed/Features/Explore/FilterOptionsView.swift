import SwiftUI

/// A list of the filter sheet.
enum FilterPicker: String, Hashable, Sendable {
    case category, brand, condition, size, wilaya

    /// Long lists get a search field.
    var isSearchable: Bool { self == .brand || self == .wilaya || self == .category }
}

/// A choice of a filter list: nil `value` is "Tout" (no filter).
struct FilterOption: Identifiable, Hashable, Sendable {
    let value: String?
    let title: String
    /// A top-level category: bold, its subcategories indented under it.
    var isGroup = false
    var isIndented = false
    /// Also matched by the search field (the wilaya's code).
    var searchText: String?

    var id: String { value ?? "" }

    /// The two levels in one list, as the website's category select: each top-level category (which
    /// includes its subcategories), then its subcategories.
    static func categories(_ categories: [CatalogCategory]) -> [FilterOption] {
        categories.flatMap { parent in
            [FilterOption(value: parent.slug, title: parent.name, isGroup: !parent.children.isEmpty)]
                + parent.children.map { FilterOption(value: $0.slug, title: $0.name, isIndented: true, searchText: parent.name) }
        }
    }

    /// Whether the option matches what the member typed: case- and accent-insensitive, on its title,
    /// its extra search text, or (for a subcategory) its category's name.
    func matches(_ typed: String) -> Bool {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if value == nil { return false }
        return [title, searchText].compactMap { $0 }.contains { $0.localizedStandardContains(query) }
    }
}

/// One filter's choices, pushed inside the filter sheet: back, the list (searchable when long), a check
/// on the current choice. Choosing goes back to the sheet.
struct FilterOptionsView: View {
    struct Remote {
        var isLoading = false
        var error: ApiError?
    }

    let title: String
    let options: [FilterOption]
    let selection: String?
    let isSearchable: Bool
    let remote: Remote
    let retry: () -> Void
    let onSelect: (String?) -> Void
    @State private var searchText = ""
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TaleedTopAppBar(title: title, onBack: { dismiss() })
            if isSearchable, options.count > 1 {
                TaleedTextField(text: $searchText, placeholder: l10n.string(.commonSearch), leadingIcon: .magnifyingGlass)
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.vertical, TaleedSpacing.s12)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        if options.count <= 1, let error = remote.error {
            ErrorStateView(error: error, retry: retry, onBack: { dismiss() })
        } else if options.count <= 1, remote.isLoading {
            LoadingStateView()
        } else {
            let shown = options.filter { $0.matches(searchText) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { option in
                        FilterOptionRow(option: option, isSelected: option.value == selection) { onSelect(option.value) }
                    }
                    if shown.isEmpty {
                        Text(l10n.string(.filtersNoResults))
                            .taleedFont(TaleedFont.bodyRegular)
                            .foregroundStyle(TaleedColor.textBody)
                            .multilineTextAlignment(.center)
                            .padding(TaleedSpacing.s24)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

/// A choice row: at least 56 high, the label (bold for a category, indented for a subcategory) and a
/// check when chosen.
struct FilterOptionRow: View {
    let option: FilterOption
    let isSelected: Bool
    /// The leading and trailing inset: the screen margin under an app bar, the sheet's padding under a
    /// sheet heading (so the rows line up with its title).
    var inset: CGFloat = TaleedLayout.screenMargin
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: TaleedSpacing.s12) {
                    Text(verbatim: option.title)
                        .taleedFont(option.isGroup || isSelected ? TaleedFont.bodyLarge.with(weight: .semibold) : TaleedFont.bodyLarge)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected { TaleedIconView(.check, size: 20, color: TaleedColor.brandPrimary) }
                }
                .padding(.vertical, TaleedSpacing.s12)
                .padding(.leading, option.isIndented ? inset + TaleedSpacing.s24 : inset)
                .padding(.trailing, inset)
                .frame(maxWidth: .infinity, minHeight: 56)
                Rectangle()
                    .fill(TaleedColor.borderSubtle)
                    .frame(height: 1)
                    .padding(.leading, inset)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
