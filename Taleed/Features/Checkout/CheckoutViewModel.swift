// One screen's whole flow (quotes, refusals, the order): kept in one place on purpose.
// swiftlint:disable file_length
import Foundation
import Observation

/// The checkout screen (screens.md §2 G11 and §7 G11, slice D "Checkout"; website `checkout/[listingId]`):
/// the goods, the delivery, the recipient, the server's summary, the promo code, the payment
/// method, then `POST /orders`.
///
/// Every change the price depends on (delivery kind, wilaya, commune, desk, promo, method) quotes
/// again; the street and the recipient do not. The order is placed once per tap with a `clientId`, and
/// sent again as it is when the member retries after a lost answer.
@MainActor
@Observable
final class CheckoutViewModel { // swiftlint:disable:this type_body_length
    /// What the screen shows.
    enum Phase: Equatable {
        case loading
        /// The form: with a quote (`pricing`), or the goods only (`preview`) until a wilaya is picked.
        case form
        /// The first load failed: an error with "Réessayer" (offline included).
        case failed(ApiError)
        /// `404`: no such listing, or a bundle that is not the member's.
        case notFound
        /// Sold, reserved by someone else, hidden, or a bundle already ordered.
        case unavailable
        /// One of the two members blocked the other.
        case blocked
        /// The member's own listing.
        case forbidden
        /// The member's own order awaiting payment holds the goods: open it (slice F).
        case heldByOrder(orderId: String)
    }

    enum Notice: Equatable {
        case error(ApiError)
        case info(L10nKey)
    }

    /// What the screen does after "Payer" / "Commander".
    enum OrderOutcome: Equatable {
        /// Open the gateway's page, then the payment screen.
        case payOnline(url: URL, orderId: String, address: AddressDraft?)
        /// Confirmed at once (cash on delivery) or waiting with "Pay now": the payment screen.
        case placed(orderId: String, address: AddressDraft?)
        /// Nothing to do: the screen stays (a notice or a field error says why).
        case stay
    }

    /// The promo field's error.
    enum PromoFieldError: Equatable {
        /// The server's localized reason (`promoError.message`).
        case server(String)
        /// Refused before the server could say why (`body.promoCode`).
        case invalid
    }

    let target: CheckoutTarget
    var form = CheckoutFormState()
    private(set) var phase: Phase = .loading
    private(set) var pricing: CheckoutPricing?
    private(set) var preview: CheckoutPreview?
    private(set) var isQuoting = false
    /// The last quote after a change failed: the summary shows it with "Réessayer".
    private(set) var quoteError: ApiError?
    private(set) var promoError: PromoFieldError?
    private(set) var isApplyingPromo = false
    private(set) var savedAddresses: [SavedAddress] = []
    /// The saved address the delivery came from; nil for a new one.
    private(set) var selectedAddressId: String?
    private(set) var communes: [CommuneOption] = []
    private(set) var isLoadingCommunes = false
    private(set) var communesError: ApiError?
    private(set) var stopdesks: [StopdeskOption] = []
    private(set) var isLoadingStopdesks = false
    private(set) var stopdesksError: ApiError?
    /// Refusals from the API, by field, until the member changes the field.
    private(set) var fieldErrors: [CheckoutField: CheckoutFieldError] = [:]
    private(set) var isPlacing = false
    var notice: Notice?

    @ObservationIgnored private let dependencies: CheckoutDependencies
    @ObservationIgnored private var api: CheckoutApi { dependencies.checkout }
    /// The request of the quote on screen, without the street (which changes no amount).
    @ObservationIgnored private var quotedRequest: CheckoutRequest?
    @ObservationIgnored private var quoteGeneration = 0
    /// The order of the last tap, kept while its answer may have been lost, to send it again as it is.
    @ObservationIgnored private var pendingOrder: OrderRequest?
    /// An order went through: nothing quotes again (the goods are now reserved by it).
    @ObservationIgnored private var hasPlacedOrder = false
    /// The wilaya `communes` / `stopdesks` belong to: nil until its list arrived.
    private var communesWilaya: Int?
    private var stopdesksWilaya: Int?
    /// One per load: a newer load (a newer wilaya) supersedes the one in flight, whose answer is dropped.
    @ObservationIgnored private var communesGeneration = 0
    @ObservationIgnored private var stopdesksGeneration = 0
    @ObservationIgnored private var communesLoadingWilaya: Int?
    @ObservationIgnored private var stopdesksLoadingWilaya: Int?

    init(target: CheckoutTarget, dependencies: CheckoutDependencies) {
        self.target = target
        self.dependencies = dependencies
    }

    // MARK: Reading

    /// The quote no longer matches the form (a change is being quoted, or its quote failed).
    var isStale: Bool {
        guard let quotedRequest, let current = form.request(for: target) else { return true }
        return quotedRequest != current.priced
    }

    var action: CheckoutAction {
        guard pricing != nil, !isStale, form.isComplete else { return .pending }
        return CheckoutAction.of(pricing)
    }

    /// The button's label once the quote is known, even while the form is incomplete ("Payer 3 420 DA").
    var displayedAction: CheckoutAction {
        guard !isStale else { return .pending }
        return CheckoutAction.of(pricing)
    }

    var canPlaceOrder: Bool { action != .pending && !isPlacing && !isQuoting }

    /// The desks of the chosen commune.
    var desksForCommune: [StopdeskOption] { CheckoutRules.desks(stopdesks, communeId: form.communeId) }

    /// The desk list on screen is the chosen wilaya's (so an empty `desksForCommune` really means none).
    var hasStopdesksForWilaya: Bool { form.wilayaId != nil && stopdesksWilaya == form.wilayaId }

    // MARK: Loading

    func loadIfNeeded() async {
        guard phase == .loading, quoteGeneration == 0, preview == nil else { return }
        await load()
    }

    func retry() async {
        phase = .loading
        await load()
    }

    private func load() async {
        quoteGeneration += 1
        do {
            #if DEBUG
            try debugFailFirstLoad()
            #endif
            let profile = try await api.checkoutProfile()
            // Saved addresses are an app extra: the form works without them.
            savedAddresses = (try? await api.savedAddresses()) ?? savedAddresses
            prefill(profile)
        } catch {
            phase = .failed(error)
            return
        }
        if form.wilayaId == nil {
            await loadPreview()
        } else {
            async let communes: Void = loadCommunes()
            await quote(initial: true)
            await communes
        }
    }

    /// The default saved address (home delivery), otherwise the profile's name, phone and wilaya.
    private func prefill(_ profile: CheckoutProfile) {
        guard form.wilayaId == nil, form.recipientName.isEmpty else { return }
        if let address = savedAddresses.first(where: \.isDefault) ?? savedAddresses.first {
            form.apply(address)
            selectedAddressId = address.id
        } else {
            form.recipientName = String(profile.name.prefix(CheckoutLimits.recipientNameMax))
            form.phone = profile.phone ?? ""
            form.wilayaId = profile.wilayaId
        }
    }

    /// The goods without a quote (no wilaya yet): the listing or the bundle.
    private func loadPreview() async {
        do {
            let preview = try await fetchPreview()
            if preview.canBuy {
                self.preview = preview
                phase = .form
            } else if let orderId = preview.orderId {
                await openHeldGoods(orderId: orderId)
            } else {
                phase = .unavailable
            }
        } catch {
            handleBlockingError(error, initial: true)
        }
    }

    /// The goods went to an order the member is part of (`orderId`, slice D): only the member's own order
    /// awaiting payment takes over checkout; a paid, shipped or completed one leaves "no longer for sale".
    private func openHeldGoods(orderId: String) async {
        do {
            let awaitsPayment = try await api.isOwnOrderAwaitingPayment(orderId: orderId)
            phase = awaitsPayment ? .heldByOrder(orderId: orderId) : .unavailable
        } catch {
            switch error.code {
            case .notFound, .forbidden: phase = .unavailable
            default: phase = .failed(error)
            }
        }
    }

    private func fetchPreview() async throws(ApiError) -> CheckoutPreview {
        if let bundleId = target.bundleId {
            let bundle = try await dependencies.bundles.bundleReview(id: bundleId, automatic: false)
            let items = bundle.availableItems.map {
                CheckoutLine(listingId: $0.listingId, title: $0.title, price: $0.price, imageURL: $0.imageURL)
            }
            return CheckoutPreview(title: "", items: items, itemPrice: bundle.itemsTotal,
                                   protectionFee: bundle.protectionFee, isBundle: true,
                                   canBuy: bundle.canBuy, orderId: bundle.status == .ordered ? bundle.orderId : nil)
        }
        let listing = try await dependencies.listings.listing(id: target.listingId, countView: false, automatic: false)
        if listing.isOwner { throw ApiError.failed(ApiFailure(status: 403, code: .forbidden)) }
        let offer = listing.acceptedOffer.flatMap { target.offerId == nil || $0.id == target.offerId ? $0 : nil }
        let line = CheckoutLine(listingId: listing.id, title: listing.title, price: offer?.amount ?? listing.price,
                                imageURL: listing.photos.first?.thumbURL ?? listing.photos.first?.url)
        return CheckoutPreview(title: listing.title, items: [line], itemPrice: offer?.amount ?? listing.price,
                               protectionFee: offer == nil ? listing.protectionFee : nil, isBundle: false,
                               canBuy: listing.canBuy, orderId: listing.orderId)
    }

    // MARK: Changes that quote again

    func selectKind(_ kind: DeliveryKind) async {
        guard kind != form.kind else { return }
        form.kind = kind
        fieldErrors[.stopdesk] = nil
        async let desksLoad: Void = loadStopdesksIfNeeded()
        await quote()
        await desksLoad
    }

    func selectWilaya(_ id: Int) async {
        guard id != form.wilayaId else { return }
        form.selectWilaya(id)
        selectedAddressId = nil
        clearFieldErrors([.wilaya, .commune, .stopdesk])
        resetReferenceLists()
        async let communesLoad: Void = loadCommunes()
        async let desksLoad: Void = loadStopdesksIfNeeded()
        await quote()
        _ = await (communesLoad, desksLoad)
    }

    func selectCommune(_ id: Int) async {
        guard id != form.communeId else { return }
        form.selectCommune(id)
        clearFieldErrors([.commune, .stopdesk])
        await quote()
    }

    func selectStopdesk(_ id: Int) async {
        guard id != form.stopdeskId else { return }
        form.stopdeskId = id
        clearFieldErrors([.stopdesk])
        await quote()
    }

    /// "Adresse enregistrée": fills home delivery from a saved address; nil: a new address.
    func selectSavedAddress(_ id: String?) async {
        guard id != selectedAddressId else { return }
        selectedAddressId = id
        let previousWilaya = form.wilayaId
        if let address = savedAddresses.first(where: { $0.id == id }) {
            form.apply(address)
        } else {
            form.communeId = nil
            form.addressLine = ""
        }
        clearFieldErrors([.recipientName, .phone, .wilaya, .commune, .addressLine])
        guard form.wilayaId != previousWilaya else {
            await quote()
            return
        }
        resetReferenceLists()
        async let communesLoad: Void = loadCommunes()
        async let desksLoad: Void = loadStopdesksIfNeeded()
        await quote()
        _ = await (communesLoad, desksLoad)
    }

    /// "Appliquer": the quote checks the code (case and spaces do not matter).
    func applyPromo() async {
        let code = form.promoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !isApplyingPromo else { return }
        promoError = nil
        guard form.wilayaId != nil else {
            // No quote is possible yet: the code waits for the wilaya, which checks it.
            form.appliedPromoCode = code
            form.promoInput = ""
            return
        }
        isApplyingPromo = true
        defer { isApplyingPromo = false }
        await quote(promoCode: code)
    }

    func removePromo() async {
        form.appliedPromoCode = nil
        promoError = nil
        await quote()
    }

    /// The promo field changed: its error goes.
    func promoInputChanged() {
        promoError = nil
    }

    func selectPaymentMethod(_ value: String) async {
        guard value != (form.paymentMethod ?? pricing?.paymentMethod) else { return }
        form.paymentMethod = value
        await quote()
    }

    /// A text field changed: its refusal from the API goes.
    func edited(_ field: CheckoutField) {
        fieldErrors[field] = nil
    }

    /// Back on screen or in the foreground: the same quote again (a fee or a voucher may have changed).
    func refresh() async {
        guard phase == .form, !hasPlacedOrder, !isPlacing else { return }
        await quote()
    }

    func retryQuote() async {
        await quote()
    }

    // MARK: Quoting

    /// Quotes the form as it is. An answer that arrives after a newer change is dropped.
    private func quote(initial: Bool = false, promoCode: String? = nil) async {
        guard !hasPlacedOrder, var request = form.request(for: target) else { return }
        if let promoCode { request.promoCode = promoCode }
        quoteGeneration += 1
        let generation = quoteGeneration
        isQuoting = true
        do {
            let pricing = try await api.quote(request)
            guard generation == quoteGeneration else { return }
            isQuoting = false
            apply(pricing, for: request, typedPromo: promoCode)
            if case .form = phase {} else { phase = .form }
        } catch {
            guard generation == quoteGeneration else { return }
            isQuoting = false
            await handleQuoteError(error, initial: initial)
        }
    }

    private func apply(_ pricing: CheckoutPricing, for request: CheckoutRequest, typedPromo: String?) {
        self.pricing = pricing
        quoteError = nil
        if request.promoCode != nil {
            if let promo = pricing.promo {
                form.appliedPromoCode = promo.code
                if typedPromo != nil { form.promoInput = "" }
                promoError = nil
            } else {
                // The code cannot be used: the rest of the quote stands, the reason shows under the field.
                form.appliedPromoCode = nil
                promoError = pricing.promoErrorMessage.map(PromoFieldError.server) ?? .invalid
            }
        }
        var quoted = request
        quoted.promoCode = form.appliedPromoCode
        if let method = form.paymentMethod, !pricing.paymentMethods.contains(where: { $0.value == method }) {
            form.paymentMethod = nil
        }
        quoted.paymentMethod = form.paymentMethod
        // The request the form now makes. A refused code leaves the rest of the quote standing, so the
        // quote also stands for the form without it.
        quotedRequest = quoted.priced
    }

    private func handleQuoteError(_ error: ApiError, initial: Bool) async {
        switch error.code {
        case .notFound, .listingUnavailable, .forbidden, .blocked:
            handleBlockingError(error, initial: initial)
        case .paymentMethodUnavailable:
            // The admin turned it off meanwhile: the server's first method, and the list again.
            form.paymentMethod = nil
            notice = .info(.checkoutErrorMethodUnavailable)
            await quote(initial: initial)
        case .invalidRequest where placeIssues(error.issues):
            await quote(initial: initial)
        default:
            if initial || phase != .form {
                phase = .failed(error)
            } else {
                quoteError = error
            }
        }
    }

    /// The states that replace the form.
    private func handleBlockingError(_ error: ApiError, initial: Bool) {
        switch error.code {
        case .notFound: phase = .notFound
        case .listingUnavailable:
            phase = error.orderId.map { .heldByOrder(orderId: $0) } ?? .unavailable
        case .forbidden: phase = .forbidden
        case .blocked: phase = .blocked
        default:
            if initial || phase != .form { phase = .failed(error) } else { notice = .error(error) }
        }
    }

    /// Shows the API's refusals on their fields and clears the choices it no longer accepts. True when
    /// at least one issue was about a choice the next quote can do without.
    private func placeIssues(_ issues: [ApiFieldIssue]) -> Bool {
        var cleared = false
        for issue in issues {
            switch issue.field {
            case "delivery.communeId":
                fieldErrors[.commune] = .pickAgain
                form.communeId = nil
                form.stopdeskId = nil
                cleared = true
            case "delivery.stopdeskId":
                fieldErrors[.stopdesk] = .pickAgain
                form.stopdeskId = nil
                cleared = true
            case "delivery.addressLine": fieldErrors[.addressLine] = .invalid
            case "recipientName": fieldErrors[.recipientName] = form.recipientNameError ?? .invalid
            case "phone": fieldErrors[.phone] = .phoneInvalid
            case "promoCode":
                form.appliedPromoCode = nil
                promoError = .invalid
                cleared = true
            case "paymentMethod":
                form.paymentMethod = nil
                cleared = true
            case "delivery.wilayaId": fieldErrors[.wilaya] = .pickAgain
            default: break
            }
        }
        return cleared
    }

    private func clearFieldErrors(_ fields: [CheckoutField]) {
        for field in fields { fieldErrors[field] = nil }
    }

    // MARK: Ordering

    /// The listings checkout is for: the listing, or the bundle's items still for sale.
    var goodsListingIds: [String] {
        var ids = [target.listingId]
        for line in pricing?.goods.items ?? preview?.items ?? [] where !ids.contains(line.listingId) {
            ids.append(line.listingId)
        }
        return ids
    }

    /// Tells the screens below that the goods changed on the server (reserved by an order, sold, held by
    /// the member's own order): the listing screen still in the stack reloads (screens.md §0.6, §7 G11).
    func noteGoodsChanged(_ changes: ListingChangeCenter?) {
        for listingId in goodsListingIds { changes?.post(.stale, listingId: listingId) }
    }

    /// "Payer 3 420 DA", "Commander — … à la livraison" or "Confirmer la commande". An order that went
    /// through reserves the goods: `changes` tells the screens below.
    func placeOrder(changes: ListingChangeCenter? = nil) async -> OrderOutcome {
        guard canPlaceOrder, let pricing, let request = form.request(for: target) else { return .stay }
        let order = orderRequest(request, pricing: pricing)
        pendingOrder = order
        isPlacing = true
        defer { isPlacing = false }
        do {
            let placed = try await api.placeOrder(order)
            pendingOrder = nil
            hasPlacedOrder = true
            noteGoodsChanged(changes)
            let address = form.unsavedAddress(among: savedAddresses)
            if let url = placed.paymentURL, placed.order.status == .pendingPayment {
                return .payOnline(url: url, orderId: placed.order.id, address: address)
            }
            return .placed(orderId: placed.order.id, address: address)
        } catch {
            return await handleOrderError(error)
        }
    }

    /// The tap's order: the one of the previous tap when nothing changed since (its answer may have been
    /// lost), otherwise a new one with a new `clientId`.
    private func orderRequest(_ request: CheckoutRequest, pricing: CheckoutPricing) -> OrderRequest {
        let candidate = OrderRequest(
            request: request,
            paymentMethod: pricing.paymentMethod,
            recipientName: form.trimmedRecipientName,
            phone: form.phone.trimmingCharacters(in: .whitespaces),
            expectedTotal: pricing.amounts.total,
            clientId: pendingOrder?.clientId ?? UUID().uuidString
        )
        if let pendingOrder, pendingOrder == candidate { return pendingOrder }
        return OrderRequest(request: candidate.request, paymentMethod: candidate.paymentMethod,
                            recipientName: candidate.recipientName, phone: candidate.phone,
                            expectedTotal: candidate.expectedTotal, clientId: UUID().uuidString)
    }

    private func handleOrderError(_ error: ApiError) async -> OrderOutcome {
        switch error.code {
        case .priceChanged:
            // Nothing was ordered: the new total, and the member taps again.
            pendingOrder = nil
            notice = .error(error)
            await quote()
        case .promoInvalid:
            pendingOrder = nil
            notice = .error(error)
            await quote()
        case .paymentMethodUnavailable:
            pendingOrder = nil
            form.paymentMethod = nil
            notice = .info(.checkoutErrorMethodUnavailable)
            await quote()
        case .notFound, .listingUnavailable, .forbidden, .blocked:
            pendingOrder = nil
            handleBlockingError(error, initial: false)
        case .invalidRequest:
            pendingOrder = nil
            _ = placeIssues(error.issues)
            notice = .error(error)
            if form.request(for: target)?.priced != quotedRequest { await quote() }
        default:
            // No answer, a 5xx, `shipping_unavailable`, `payment_unavailable`: the order may have gone
            // through; the next tap sends the same one again (same `clientId`).
            notice = .error(error)
        }
        return .stay
    }

    #if DEBUG
    @ObservationIgnored private var debugFailed = false

    /// `-TaleedDebugCheckout offline` fails the first load (screenshots of the offline state).
    private func debugFailFirstLoad() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugCheckout") == "offline", !debugFailed else { return }
        debugFailed = true
        throw .network
    }
    #endif
}

// MARK: - Reference lists

extension CheckoutViewModel {
    /// A new wilaya: its communes and desks are other ones. The lists and the wilaya they belong to go,
    /// and the loads in flight are superseded (their answers are dropped).
    private func resetReferenceLists() {
        communes = []
        communesWilaya = nil
        communesError = nil
        communesLoadingWilaya = nil
        communesGeneration += 1
        isLoadingCommunes = false
        stopdesks = []
        stopdesksWilaya = nil
        stopdesksError = nil
        stopdesksLoadingWilaya = nil
        stopdesksGeneration += 1
        isLoadingStopdesks = false
    }

    /// The wilaya's communes, for the commune picker. Joins a load of the same wilaya; a newer wilaya's
    /// load supersedes an older one, so the list on screen is always the chosen wilaya's.
    func loadCommunes() async {
        guard let wilaya = form.wilayaId, communesWilaya != wilaya || communesError != nil,
              communesLoadingWilaya != wilaya else { return }
        communesGeneration += 1
        let generation = communesGeneration
        communesLoadingWilaya = wilaya
        isLoadingCommunes = true
        communesError = nil
        let result: Result<[CommuneOption], ApiError>
        do {
            result = .success(try await api.communes(wilayaId: wilaya))
        } catch {
            result = .failure(error)
        }
        // A newer load owns the state now.
        guard generation == communesGeneration else { return }
        communesLoadingWilaya = nil
        isLoadingCommunes = false
        guard form.wilayaId == wilaya else {
            // The wilaya changed without a load of its own: the chosen one's list, now.
            await loadCommunes()
            return
        }
        switch result {
        case let .success(list):
            communes = list
            communesWilaya = wilaya
        case let .failure(error):
            communesError = error
        }
    }

    /// The desks, when the delivery goes to one.
    func loadStopdesksIfNeeded() async {
        if form.kind == .stopdesk { await loadStopdesks() }
    }

    /// The wilaya's desks, for stop-desk delivery. Same rules as the communes.
    func loadStopdesks() async {
        guard let wilaya = form.wilayaId, stopdesksWilaya != wilaya || stopdesksError != nil,
              stopdesksLoadingWilaya != wilaya else { return }
        stopdesksGeneration += 1
        let generation = stopdesksGeneration
        stopdesksLoadingWilaya = wilaya
        isLoadingStopdesks = true
        stopdesksError = nil
        let result: Result<[StopdeskOption], ApiError>
        do {
            result = .success(try await api.stopdesks(wilayaId: wilaya))
        } catch {
            result = .failure(error)
        }
        guard generation == stopdesksGeneration else { return }
        stopdesksLoadingWilaya = nil
        isLoadingStopdesks = false
        guard form.wilayaId == wilaya else {
            await loadStopdesksIfNeeded()
            return
        }
        switch result {
        case let .success(list):
            stopdesks = list
            stopdesksWilaya = wilaya
        case let .failure(error):
            stopdesksError = error
        }
    }
}

extension CheckoutRequest {
    /// The request without the street, which changes no amount (a typed street never quotes again).
    var priced: CheckoutRequest {
        var request = self
        request.delivery.addressLine = nil
        return request
    }
}
