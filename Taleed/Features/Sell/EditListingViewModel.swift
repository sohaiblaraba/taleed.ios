import Foundation
import Observation

/// The edit form's screen (screens.md §2 G8; slice B, Editing; website `listings/[id]/edit`): loads
/// the listing with `GET /listings/{id}`, opens the form only for the seller's listing while its
/// status allows editing, and saves through the form (`SellViewModel` in edit mode).
@MainActor
@Observable
final class EditListingViewModel {
    enum Phase {
        case loading
        /// The load failed: the error with Retry (offline included).
        case failed(ApiError)
        /// `404`, or not the member's listing (as the website's edit page).
        case notFound
        /// Reserved, sold or another status that cannot change (the website goes back to the listing).
        case locked
        case ready(SellViewModel)
    }

    let listingId: String
    private(set) var phase: Phase = .loading
    /// The listing was edited somewhere else and reloaded into the form: the notice above the button.
    private(set) var showsReloadNotice = false

    @ObservationIgnored private let api: EditListingApi
    @ObservationIgnored private let upload: (Data) async throws(ApiError) -> UploadedPhoto
    @ObservationIgnored private let brands: () async -> [CatalogBrand]
    @ObservationIgnored private let memberWilayaId: () -> Int?
    @ObservationIgnored private let refreshLists: (Set<SellReferenceList>) async -> Void
    @ObservationIgnored private var isLoading = false

    /// `brands`: `GET /brands` (to preselect a catalog brand), an empty list when it fails.
    init(listingId: String, api: EditListingApi, upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto,
         brands: @escaping () async -> [CatalogBrand], memberWilayaId: @escaping () -> Int?,
         refreshLists: @escaping (Set<SellReferenceList>) async -> Void = { _ in }) {
        self.listingId = listingId
        self.api = api
        self.upload = upload
        self.brands = brands
        self.memberWilayaId = memberWilayaId
        self.refreshLists = refreshLists
    }

    var form: SellViewModel? {
        if case let .ready(form) = phase { return form }
        return nil
    }

    // MARK: Loading

    /// The first load, once (the screen's `.task`).
    func loadIfNeeded() async {
        guard case .loading = phase else { return }
        await load()
    }

    /// "Retry" after a failed load.
    func retry() async {
        phase = .loading
        await load()
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            #if DEBUG
            try debugFailFirstLoad()
            #endif
            let listing = try await api.editableListing(id: listingId)
            switch ListingEditability(listing) {
            case .notOwner:
                phase = .notFound
            case .locked:
                phase = .locked
            case .editable:
                let brands = await brands()
                phase = .ready(SellViewModel(editing: listing, brands: brands, memberWilayaId: memberWilayaId(),
                                             api: api, upload: upload, refreshLists: refreshLists))
            }
        } catch {
            phase = error.isNotFound ? .notFound : .failed(error)
        }
    }

    // MARK: Saving

    /// "Enregistrer les modifications". When the API says the listing changed somewhere else, the listing
    /// is loaded again into the form (its photos as they are now), and the member checks it and saves again.
    func save() async -> ListingSaveOutcome {
        guard let form else { return .refused }
        showsReloadNotice = false
        let outcome = await form.save()
        switch outcome {
        case .listingChanged:
            return await reloadIntoForm(form)
        case .gone:
            phase = .notFound
            return outcome
        case .saved, .refused, .cannotEdit:
            return outcome
        }
    }

    private func reloadIntoForm(_ form: SellViewModel) async -> ListingSaveOutcome {
        do {
            let listing = try await api.editableListing(id: listingId)
            switch ListingEditability(listing) {
            case .editable:
                form.reloadListing(listing, brands: await brands())
                showsReloadNotice = true
                return .listingChanged
            case .locked:
                return .cannotEdit(.failed(ApiFailure(status: 409, code: .listingLocked)))
            case .notOwner:
                phase = .notFound
                return .gone
            }
        } catch {
            if error.isNotFound {
                phase = .notFound
                return .gone
            }
            // The notice still asks to check the photos; Save sends the same request again.
            showsReloadNotice = true
            return .refused
        }
    }

    #if DEBUG
    @ObservationIgnored private var debugFailed = false

    /// `-TaleedDebugEditListing offline` fails the first load (screenshots of the offline state).
    private func debugFailFirstLoad() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugEditListing") == "offline", !debugFailed else { return }
        debugFailed = true
        throw .network
    }
    #endif
}
