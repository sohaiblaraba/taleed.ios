import SwiftUI

struct HomeView: View {
    let viewModel: HomeViewModel
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        content
            .navigationTitle(l10n.string(.tabHome))
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
            List {
                if categories.isEmpty {
                    Text(l10n.string(.commonEmpty))
                        .foregroundStyle(.secondary)
                } else {
                    Section(l10n.string(.homeCategories)) {
                        ForEach(categories) { category in
                            Text(category.name)
                                .frame(minHeight: Theme.minTouchTarget, alignment: .leading)
                        }
                    }
                }
            }
            .refreshable { await viewModel.load() }
        }
    }
}
