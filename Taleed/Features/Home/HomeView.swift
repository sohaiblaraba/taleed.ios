import SwiftUI

/// Home, for now the top-level categories (the real Home comes later).
struct HomeView: View {
    let viewModel: HomeViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(ShellRouter.self) private var router

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
        case let .loaded(categories):
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                    searchField
                    if categories.isEmpty {
                        MessageStateView(text: l10n.string(.commonEmpty), icon: .magnifyingGlass)
                    } else {
                        SectionTitle(text: l10n.string(.homeCategories))
                            .padding(.top, TaleedSpacing.s8)
                        VStack(spacing: 0) {
                            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                                TaleedListRow(title: category.name, showsDivider: index < categories.count - 1)
                            }
                        }
                        .taleedCard()
                        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                    }
                }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.top, TaleedSpacing.s8)
                .padding(.bottom, TaleedSpacing.s24)
            }
            .refreshable { await viewModel.load() }
        }
    }

    /// Looks like the search field; opens Explore.
    private var searchField: some View {
        Button { router.selectedTab = .explore } label: {
            HStack(spacing: TaleedSize.Input.gap) {
                TaleedIconView(.magnifyingGlass, size: TaleedSize.Input.iconLeading, color: TaleedColor.textSecondary)
                Text(l10n.string(.homeSearchPlaceholder))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, TaleedSize.Input.paddingX)
            .frame(minHeight: TaleedSize.Input.height)
            .taleedCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.string(.homeSearchPlaceholder))
        .accessibilityAddTraits(.isSearchField)
    }
}
