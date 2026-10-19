import SwiftUI

/// Home, for now the top-level categories (the real Home comes later).
struct HomeView: View {
    let viewModel: HomeViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router

    var body: some View {
        ShellScreen {
            ShellBrandAppBar(showsDivider: false)
        } content: {
            content
        }
        .task {
            if viewModel.state == .loading { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView()
        case let .failed(error):
            ErrorStateView(error: error) { Task { await viewModel.retry() } }
        case let .loaded(categories) where categories.isEmpty:
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.top, TaleedSpacing.s8)
                MessageStateView(text: l10n.string(.commonEmpty))
            }
            .refreshable { await viewModel.retry() }
        case let .loaded(categories):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    searchField
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.top, TaleedSpacing.s8)
                    // Flat full-width rows with start-inset dividers, as Android's Home list.
                    SectionTitle(text: l10n.string(.homeCategories))
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.top, TaleedSpacing.s24)
                        .padding(.bottom, TaleedSpacing.s8)
                    LazyVStack(spacing: 0) {
                        ForEach(categories) { category in
                            ListRow(label: category.name, showsChevron: true) {
                                router.push(.search(ExploreQuery(category: category.slug)))
                            }
                        }
                    }
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
            .refreshable { await viewModel.retry() }
        }
    }

    /// Looks like the search field but is a button that opens Explore, so VoiceOver announces a button
    /// with a hint, not a search field.
    private var searchField: some View {
        Button { router.selectedTab = .explore } label: {
            HStack(spacing: TaleedSize.inputGap) {
                TaleedIconView(.magnifyingGlass, size: TaleedSize.inputIconLeading, color: TaleedColor.textSecondary)
                Text(l10n.string(.homeSearchHint))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, TaleedSize.inputPaddingX)
            .frame(minHeight: TaleedSize.inputHeight)
            .taleedCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.string(.homeSearchHint))
        .accessibilityHint(l10n.string(.a11yOpensExplore))
    }
}
