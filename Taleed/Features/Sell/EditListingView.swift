import SwiftUI

/// What the edit form needs besides the shared stores. Set once at the root (`AppRootView`).
struct EditListingDependencies {
    let api: any EditListingApi
    let uploads: PhotoUploadService
}

private struct EditListingDependenciesKey: EnvironmentKey {
    static var defaultValue: EditListingDependencies? { nil }
}

extension EnvironmentValues {
    var editListingDependencies: EditListingDependencies? {
        get { self[EditListingDependenciesKey.self] }
        set { self[EditListingDependenciesKey.self] = newValue }
    }
}

/// Edit listing (screens.md §2 G8 and §7 G8; Figma "Sell an Item" as the edit form; website
/// `listings/[id]/edit`): back and "Modifier l'annonce", then the sell form filled from the listing,
/// with "Enregistrer les modifications". Pushed from the listing screen and from My listings (the
/// website's `/listings/{id}/edit` link goes Home, screens.md §1.2).
///
/// States: loading, the error with Retry (offline included), "no longer available" (`404`, or not the
/// member's listing), and a notice when the listing can no longer change (reserved, sold). Saved: the
/// toast "Annonce mise à jour.", then back to the screen below, which shows the new values.
/// `listing_locked` while saving: the message, then back to the listing, which reloads.
struct EditListingView: View {
    @State private var model: EditListingViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @Environment(ListingChangeCenter.self) private var listingChanges
    @Environment(FavoriteStore.self) private var favorites
    @Environment(\.dismiss) private var dismiss

    init(listingId: String, dependencies: EditListingDependencies, references: ExploreReferenceStore,
         catalog: CatalogStore, session: SessionManager) {
        let uploads = dependencies.uploads
        _model = State(initialValue: EditListingViewModel(
            listingId: listingId,
            api: dependencies.api,
            upload: { data async throws(ApiError) in try await uploads.upload(data, purpose: .listingPhoto) },
            brands: {
                await references.loadBrands()
                return references.brands.value ?? []
            },
            memberWilayaId: { session.user?.wilayaId },
            refreshLists: { lists in
                if lists.contains(.catalog) { await catalog.refresh() }
                if lists.contains(.brands) { await references.refreshBrands() }
            }
        ))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.sellEditTitle), onBack: { dismiss() })
        } content: {
            content
        }
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingStateView()
        case let .failed(error):
            ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
        case .notFound:
            NotFoundStateView(title: l10n.string(.listingUnavailable), onBack: { dismiss() })
        case .locked:
            MessageStateView(text: l10n.string(.appErrorListingLocked)) {
                TaleedButton(title: l10n.string(.commonBack), kind: .tertiary, size: .medium) { dismiss() }
            }
            .accessibilityIdentifier("editListing.locked")
        case let .ready(form):
            SellFormView(model: form, showsHeading: false, submitTitle: .sellUpdate,
                         notice: model.showsReloadNotice ? l10n.string(.appEditListingReloaded) : nil) {
                await save()
            }
        }
    }

    private func save() async {
        let listingId = model.listingId
        switch await model.save() {
        case let .saved(listing):
            listingChanges.post(.updated(listing), listingId: listingId)
            toasts.show(l10n.string(.sellUpdated))
            dismiss()
        case let .cannotEdit(error):
            // It just sold or was reserved: the screens below reload it.
            toasts.show(error: error)
            listingChanges.post(.stale, listingId: listingId)
            dismiss()
        case .gone:
            favorites.markRemoved(listingId)
            listingChanges.post(.deleted, listingId: listingId)
        case .refused, .listingChanged:
            // The errors, or the reloaded listing with its notice, are on screen.
            break
        }
    }
}
