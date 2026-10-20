import SwiftUI

/// The Sell tab (screens.md §1.1, §2 G7): the brand app bar and the page heading of Figma "Sell an
/// Item", then the form. Signed out: the sign-in prompt (§0.5). A new form for each member who signs in.
struct SellView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(\.sellDependencies) private var dependencies
    @Environment(CatalogStore.self) private var catalog
    @Environment(ExploreReferenceStore.self) private var references
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(ListingChangeCenter.self) private var listingChanges
    @State private var model: SellViewModel?

    var body: some View {
        ShellScreen {
            ShellBrandAppBar()
        } content: {
            if session.isSignedIn, let model {
                SellFormView(model: model) { await publish(model) }
            } else {
                VStack(spacing: 0) {
                    PageHeading(eyebrow: l10n.string(.tabSell), title: l10n.string(.sellTitle))
                    if session.isSignedIn {
                        LoadingStateView()
                    } else {
                        SignInPromptView(icon: .storefront, title: l10n.string(.appSellSignedOutTitle))
                    }
                }
            }
        }
        // No drafts (§7 G7): another member (or none) starts from an empty form.
        .task(id: session.user?.id) {
            guard let dependencies, session.user != nil else {
                model = nil
                return
            }
            let uploads = dependencies.uploads
            let catalog = catalog
            let references = references
            model = SellViewModel(api: dependencies.api,
                                  upload: { data async throws(ApiError) in try await uploads.upload(data, purpose: .listingPhoto) },
                                  wilayaId: session.user?.wilayaId,
                                  refreshLists: { lists in
                                      // "Choose again" offers what the API knows now.
                                      if lists.contains(.catalog) { await catalog.refresh() }
                                      if lists.contains(.brands) { await references.refreshBrands() }
                                  })
        }
        .onChange(of: session.user?.wilayaId) { _, wilayaId in model?.memberWilayaDidLoad(wilayaId) }
    }

    private func publish(_ model: SellViewModel) async {
        guard let listingId = await model.publish() else { return }
        toasts.show(l10n.string(.sellPublished))
        // My listings shows it in its Active tab.
        listingChanges.post(.created, listingId: listingId)
        model.reset(wilayaId: session.user?.wilayaId)
        router.push(.listing(id: listingId))
    }
}
