import Foundation
import Observation

/// Saved addresses (screens.md §2 G16 item 9, slice D "Saved addresses"): the default first, 10 at most.
/// Add and edit in a form, "Définir par défaut", and delete after a confirmation; a `404` on a delete
/// means it was already done.
@MainActor
@Observable
final class AddressesViewModel {
    enum Notice: Equatable {
        case deleted
        case error(ApiError)
    }

    private(set) var addresses: [SavedAddress]?
    private(set) var loadError: ApiError?
    /// The addresses an action is running on: their buttons wait.
    private(set) var busyIds: Set<String> = []
    var notice: Notice?

    @ObservationIgnored private let api: AddressesApi

    init(api: AddressesApi) {
        self.api = api
    }

    /// Under 10: "Ajouter une adresse" works; at 10 it says why not.
    var canAdd: Bool { (addresses?.count ?? 0) < AccountLimits.addressesMax }

    func loadIfNeeded() async {
        guard addresses == nil, loadError == nil else { return }
        await reload()
    }

    func retry() async {
        loadError = nil
        await reload()
    }

    /// Pull-to-refresh and after every change. A failure keeps what is on screen and says so.
    func reload(automatic: Bool = false) async {
        do {
            addresses = try await api.addresses(automatic: automatic)
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            if addresses == nil {
                loadError = error
            } else if !automatic {
                notice = .error(error)
            }
        }
    }

    /// `isDefault: true` makes it the default in place of the current one.
    func makeDefault(id: String) async {
        guard !busyIds.contains(id) else { return }
        busyIds.insert(id)
        defer { busyIds.remove(id) }
        do {
            _ = try await api.updateAddress(id: id, changes: AddressChanges(isDefault: true))
            await reload(automatic: true)
        } catch {
            notice = .error(error)
        }
    }

    /// After the confirmation. Deleting the default makes the most recent one the default: the list reloads.
    func delete(id: String) async {
        guard !busyIds.contains(id) else { return }
        busyIds.insert(id)
        defer { busyIds.remove(id) }
        do {
            try await api.deleteAddress(id: id)
        } catch {
            // A repeat after it went through: already gone.
            guard error.isNotFound else {
                notice = .error(error)
                return
            }
        }
        addresses?.removeAll { $0.id == id }
        notice = .deleted
        await reload(automatic: true)
    }

    /// The form saved an address: the order (and the default) come from the server.
    func saved() async {
        await reload(automatic: true)
    }
}

/// The address form (add or edit): the recipient (2 to 80), the phone, the wilaya, its commune
/// (`GET /wilayas/{id}/communes`; a new wilaya needs its commune), the address (1 to 200), and "Utiliser
/// comme adresse par défaut". A new address is never sent twice: the button waits for the answer.
@MainActor
@Observable
final class AddressFormViewModel {
    var form: AddressForm
    let editing: SavedAddress?
    /// The first address is always the default: no switch then.
    let isFirst: Bool
    private(set) var communes: [CommuneOption] = []
    private(set) var communesError: ApiError?
    private(set) var isLoadingCommunes = false
    private(set) var showsDeviceErrors = false
    private(set) var apiErrors: [AddressField: AddressFieldError] = [:]
    private(set) var isSending = false
    var notice: ApiError?

    @ObservationIgnored private let api: AddressesApi
    @ObservationIgnored private let saved: AddressForm

    init(api: AddressesApi, editing: SavedAddress?, isFirst: Bool, recipientName: String?, phone: String?) {
        self.api = api
        self.editing = editing
        self.isFirst = isFirst
        let start = editing.map(AddressForm.init)
            ?? AddressForm(recipientName: recipientName ?? "", phone: phone ?? "", isDefault: isFirst)
        form = start
        saved = start
        // An address saved before communes came from the carrier: its commune is picked again.
        if editing != nil, start.communeId == nil { showsDeviceErrors = true }
    }

    /// Shows the switch: not for the first address, nor for the one already the default.
    var showsDefaultSwitch: Bool { !isFirst && editing?.isDefault != true }

    var canSave: Bool {
        guard !isSending else { return false }
        return editing == nil || form != saved
    }

    func error(_ field: AddressField) -> AddressFieldError? {
        if let error = apiErrors[field] { return error }
        guard showsDeviceErrors, let error = form.errors()[field] else { return nil }
        // The saved address has no commune id yet (saved before communes came from the carrier), and its
        // wilaya is unchanged: the member picks the commune again.
        if field == .commune, let editing, editing.communeId == nil, form.wilayaId == editing.wilaya.id { return .communeAgain }
        return error
    }

    func edited(_ field: AddressField) {
        apiErrors[field] = nil
    }

    /// The communes of the wilaya already chosen (editing).
    func loadIfNeeded() async {
        guard let wilayaId = form.wilayaId, communes.isEmpty, !isLoadingCommunes else { return }
        await loadCommunes(wilayaId: wilayaId)
    }

    func selectWilaya(_ id: Int) async {
        guard id != form.wilayaId else { return }
        form.wilayaId = id
        form.communeId = nil
        communes = []
        edited(.wilaya)
        edited(.commune)
        await loadCommunes(wilayaId: id)
    }

    func selectCommune(_ id: Int) {
        form.communeId = id
        edited(.commune)
    }

    func retryCommunes() async {
        guard let wilayaId = form.wilayaId else { return }
        await loadCommunes(wilayaId: wilayaId)
    }

    private func loadCommunes(wilayaId: Int) async {
        isLoadingCommunes = true
        communesError = nil
        defer { isLoadingCommunes = false }
        do {
            let loaded = try await api.communes(wilayaId: wilayaId)
            guard form.wilayaId == wilayaId else { return }
            communes = loaded
        } catch {
            guard form.wilayaId == wilayaId else { return }
            communesError = error
        }
    }

    /// Saves and returns the address, or nil when the form shows why not.
    func save() async -> SavedAddress? {
        guard !isSending else { return nil }
        showsDeviceErrors = true
        guard form.errors().isEmpty, let input = form.input else { return nil }
        isSending = true
        defer { isSending = false }
        do {
            if let editing {
                let changes = form.changes(from: saved)
                if changes.isEmpty { return editing }
                return try await api.updateAddress(id: editing.id, changes: changes)
            }
            return try await api.createAddress(input)
        } catch {
            let fields = error.code == .invalidRequest ? error.issues.compactMap { AddressForm.field(ofIssue: $0.path) } : []
            if fields.isEmpty {
                notice = error
            } else {
                for field in fields { apiErrors[field] = .invalid }
            }
            return nil
        }
    }
}
