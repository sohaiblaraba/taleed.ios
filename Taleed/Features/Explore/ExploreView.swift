import SwiftUI

/// The Explore tab (screens.md §2 G3 screen 1): the search app bar ("Search for an item", Figma
/// navigation patterns) with the photo-search button while the field is empty and photo search is on,
/// then the catalog's categories: "Tout", each top-level category opening onto "Tout" and its
/// subcategories. "Search" and each category open the results on this tab.
struct ExploreView: View {
    @State private var text = ""
    @State private var expanded: Set<String> = []
    @State private var showsVisualSearch = false
    @State private var visualSearch: VisualSearchModel?
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(CatalogStore.self) private var catalog
    @Environment(LaunchViewModel.self) private var launch
    @Environment(AppToasts.self) private var toasts
    @Environment(\.exploreDependencies) private var dependencies

    var body: some View {
        ShellScreen {
            SearchAppBar(text: $text, placeholder: l10n.string(.appExploreSearchPlaceholder), onSubmit: search,
                         onCamera: cameraAction,
                         cameraAccessibilityLabel: l10n.string(.navVisualSearch))
                .textInputAutocapitalization(.never)
                .onChange(of: text) { _, value in
                    if value.utf16.count > ListingSearchParameters.maxTextLength {
                        text = value.prefix(utf16Units: ListingSearchParameters.maxTextLength)
                    }
                }
        } content: {
            content
        }
        // Made before the sheet opens: the sheet's content is built from the state of that moment.
        .onAppear {
            if visualSearch == nil, let dependencies { visualSearch = VisualSearchModel(api: dependencies.explore) }
        }
        .taleedSheet(isPresented: $showsVisualSearch, onDismiss: { visualSearch?.reset() }, content: {
            if let visualSearch {
                VisualSearchSheet(model: visualSearch, onOutcome: visualSearchEnded)
                    .appLanguage(l10n.language)
            }
        })
    }

    @ViewBuilder
    private var content: some View {
        if let categories = catalog.catalog?.categories {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    SectionTitle(text: l10n.string(.homeCategories))
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.top, TaleedSpacing.s16)
                        .padding(.bottom, TaleedSpacing.s4)
                    ListRow(label: l10n.string(.navAllItems), leadingIcon: .storefront, showsChevron: true) {
                        router.push(.search(ExploreQuery()))
                    }
                    ForEach(categories) { category in
                        categoryRows(category)
                    }
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await catalog.refresh() }
        } else if let error = catalog.error {
            ErrorStateView(error: error) { Task { await catalog.refresh() } }
        } else {
            LoadingStateView()
                .task { if !catalog.isRefreshing { await catalog.refresh() } }
        }
    }

    // MARK: Categories

    @ViewBuilder
    private func categoryRows(_ category: CatalogCategory) -> some View {
        let isExpanded = expanded.contains(category.slug)
        CategoryDisclosureRow(title: category.name, icon: HomeCategoryIcon.icon(forSlug: category.slug),
                              isExpanded: isExpanded, hasChildren: !category.children.isEmpty) {
            if category.children.isEmpty {
                router.push(.search(ExploreQuery(category: category.slug)))
            } else {
                withAnimation(.easeInOut(duration: TaleedMotion.transitionMin)) {
                    if isExpanded { expanded.remove(category.slug) } else { expanded.insert(category.slug) }
                }
            }
        }
        if isExpanded {
            // "Tout" first: a top-level category includes its subcategories.
            SubcategoryRow(title: l10n.string(.navAllItems)) {
                router.push(.search(ExploreQuery(category: category.slug)))
            }
            ForEach(category.children) { child in
                SubcategoryRow(title: child.name) {
                    router.push(.search(ExploreQuery(category: child.slug)))
                }
            }
        }
    }

    // MARK: Actions

    /// The photo-search button, while `features.visualSearch` is on (hidden otherwise, screens.md §2 G3).
    private var cameraAction: (() -> Void)? {
        guard launch.isVisualSearchEnabled, visualSearch != nil else { return nil }
        return { openVisualSearch() }
    }

    /// "Search": the results of the keywords; an empty field shows everything, as the website does.
    private func search() {
        router.push(.search(ExploreQuery().searching(text)))
    }

    private func openVisualSearch() {
        guard visualSearch != nil else { return }
        showsVisualSearch = true
    }

    private func visualSearchEnded(_ outcome: VisualSearchModel.Outcome) {
        showsVisualSearch = false
        switch outcome {
        case let .found(id):
            router.push(.visualSearch(id: id))
        case .disabled:
            // Taleed turned it off meanwhile: hide the button and read the configuration again.
            toasts.show(l10n.string(.visualErrorDisabled), kind: .error)
            Task { await launch.visualSearchWasDisabled() }
        case .failed:
            break
        }
    }
}

/// A top-level category: its icon (Home's five), the name, and a caret that turns when it opens.
private struct CategoryDisclosureRow: View {
    let title: String
    let icon: TaleedIcon?
    let isExpanded: Bool
    let hasChildren: Bool
    let action: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(LanguageManager.self) private var l10n
    /// Grows with the text like the "Tout" row's icon (`ListRow`, up to 36 pt), so the labels line up.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: TaleedSpacing.s12) {
                    TaleedIconView(icon ?? .tShirt, size: min(iconSize, 36), color: TaleedColor.brandOnTintStrong)
                        .opacity(icon == nil ? 0 : 1)
                    Text(title)
                        .taleedFont(TaleedFont.bodyLarge)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TaleedIconView(hasChildren ? .caretDown : .caretRight, size: 18, color: TaleedColor.textSecondary)
                        .rotationEffect(.degrees(hasChildren && isExpanded ? 180 : 0))
                }
                .padding(.vertical, TaleedSpacing.s12)
                .padding(.horizontal, TaleedLayout.screenMargin)
                .frame(maxWidth: .infinity, minHeight: 56)
                Rectangle()
                    .fill(TaleedColor.borderSubtle)
                    .frame(height: 1)
                    .padding(.leading, TaleedLayout.screenMargin)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        // A disclosure row says whether its subcategories are shown, not "selected"; a category without
        // subcategories opens its results, like a plain link.
        .accessibilityValue(hasChildren ? l10n.string(isExpanded ? .appA11yExpanded : .appA11yCollapsed) : "")
        .accessibilityAddTraits(.isButton)
    }
}

/// A subcategory under its open category: indented on the grouped fill, opening its results.
private struct SubcategoryRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: TaleedSpacing.s12) {
                    Text(title)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TaleedIconView(.caretRight, size: 16, color: TaleedColor.textSecondary)
                }
                .padding(.vertical, TaleedSpacing.s12)
                .padding(.leading, TaleedLayout.screenMargin + TaleedSpacing.s32)
                .padding(.trailing, TaleedLayout.screenMargin)
                .frame(maxWidth: .infinity, minHeight: 48)
                Rectangle()
                    .fill(TaleedColor.borderSubtle)
                    .frame(height: 1)
                    .padding(.leading, TaleedLayout.screenMargin + TaleedSpacing.s32)
                    .accessibilityHidden(true)
            }
            .background(TaleedColor.surfaceGrouped)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}
