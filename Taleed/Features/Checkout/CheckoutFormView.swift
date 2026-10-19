import SwiftUI

/// A choice list of the checkout form. Short lists open in a content-sized sheet; long ones (wilayas,
/// communes) full height with a search field, as on the sell form.
enum CheckoutPicker: String, Identifiable, Hashable {
    case savedAddress, wilaya, commune, stopdesk

    var id: String { rawValue }
    var isLong: Bool { self == .wilaya || self == .commune }
}

/// The checkout form (Figma Buy Now, wireframes.md §3): heading, goods, delivery method, delivery
/// address, summary, promo code, wallet, payment method and the button. Padding 24 / 16 / 48, 24
/// between groups, 8 between the delivery options and 16 between the address fields.
struct CheckoutFormView: View {
    @Bindable var model: CheckoutViewModel
    let isInBrowser: Bool
    let pay: () -> Void
    @State var picker: CheckoutPicker?
    @State var showsFeeInfo = false
    /// Fields the member has left once: their checks show from then on.
    @State var leftFields: Set<CheckoutField> = []
    @FocusState var recipientFocused: Bool
    @FocusState var phoneFocused: Bool
    @Environment(LanguageManager.self) var l10n
    @Environment(CatalogStore.self) var catalog
    @Environment(AppRouter.self) var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeading(eyebrow: l10n.string(.checkoutSummary), title: l10n.string(.checkoutTitle))
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    goods
                    deliveryMethod
                    deliveryAddress
                    summary
                    promo
                    wallet
                    paymentMethods
                    payButton
                }
                .padding(.top, TaleedSpacing.s24)
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.bottom, TaleedSpacing.s48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("checkout.scroll")
        .onChange(of: recipientFocused) { wasFocused, _ in if wasFocused { leftFields.insert(.recipientName) } }
        .onChange(of: phoneFocused) { wasFocused, _ in if wasFocused { leftFields.insert(.phone) } }
        .taleedSheet(isPresented: shortPickerBinding) { shortPicker }
        .sheet(item: longPickerBinding) { picker in
            longPicker(picker).appLanguage(l10n.language)
        }
    }

    // MARK: Goods

    @ViewBuilder
    private var goods: some View {
        if let pricing = model.pricing {
            if pricing.goods.bundleId != nil {
                CheckoutBundleCard(items: pricing.goods.items, label: l10n.format(.checkoutBundleItems, pricing.goods.items.count),
                                   total: pricing.goods.itemPrice)
            } else if let item = pricing.goods.items.first {
                CheckoutItem(title: item.title, price: pricing.goods.itemPrice, media: .remote(item.imageURL))
                    .accessibilityIdentifier("checkout.item")
            }
            if let offer = pricing.goods.offer, offer.amount != pricing.goods.listedPrice {
                InlineAlert(kind: .success,
                            title: l10n.format(.offersAcceptedBanner, PriceFormatter.format(offer.amount, language: l10n.language)))
            }
        } else if let preview = model.preview {
            if preview.isBundle {
                CheckoutBundleCard(items: preview.items, label: l10n.format(.checkoutBundleItems, preview.items.count),
                                   total: preview.itemPrice)
            } else if let item = preview.items.first {
                CheckoutItem(title: item.title, price: preview.itemPrice, media: .remote(item.imageURL))
            }
        }
    }

    // MARK: Delivery method

    private var deliveryMethod: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            Eyebrow(text: l10n.string(.checkoutDeliveryMethod))
                .accessibilityAddTraits(.isHeader)
            ForEach(DeliveryKind.allCases, id: \.self) { kind in
                DeliveryOption(
                    icon: kind == .home ? .house : .storefront,
                    title: l10n.string(kind == .home ? .checkoutHome : .checkoutStopdesk),
                    description: l10n.string(kind == .home ? .checkoutHomeDesc : .checkoutStopdeskDesc),
                    selected: model.form.kind == kind,
                    fee: fee(for: kind)
                ) {
                    Task { await model.selectKind(kind) }
                }
                .accessibilityIdentifier("checkout.delivery.\(kind.rawValue)")
            }
            if let fees = model.pricing?.fees, !fees.exact {
                FieldHelper(text: l10n.string(.appCheckoutFeeEstimateHint))
                    .accessibilityIdentifier("checkout.feeEstimate")
            }
        }
    }

    /// Each kind's fee from the quote: the wilaya's highest ("jusqu'à 600 DA") until a commune is picked.
    private func fee(for kind: DeliveryKind) -> String? {
        guard let fees = model.pricing?.fees else { return nil }
        return feeText(fees.fee(for: kind), exact: fees.exact)
    }

    func feeText(_ amount: Int, exact: Bool) -> String {
        let price = PriceFormatter.format(amount, language: l10n.language)
        return exact ? price : l10n.format(.appCheckoutFeeUpTo, price)
    }

    // MARK: Delivery address

    private var deliveryAddress: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            Eyebrow(text: l10n.string(.appCheckoutDeliveryAddress))
                .accessibilityAddTraits(.isHeader)
            if model.form.kind == .home, !model.savedAddresses.isEmpty {
                TaleedSelectField(label: l10n.string(.appCheckoutSavedAddress), value: selectedAddressTitle,
                                  placeholder: l10n.string(.appCheckoutNewAddress), isActive: picker == .savedAddress) {
                    open(.savedAddress)
                }
                .accessibilityIdentifier("checkout.savedAddress")
            }
            TaleedTextField(label: l10n.string(.checkoutRecipientName), text: recipientBinding,
                            error: fieldError(.recipientName).map(message), focus: $recipientFocused)
                .textContentType(.name)
                .submitLabel(.next)
                .onSubmit { phoneFocused = true }
                .accessibilityIdentifier("checkout.recipient")
            TaleedTextField(label: l10n.string(.checkoutPhone), text: phoneBinding, placeholder: "0550 12 34 56",
                            helper: l10n.string(.checkoutPhoneHint), error: fieldError(.phone).map(message), focus: $phoneFocused)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .accessibilityIdentifier("checkout.phone")
            TaleedSelectField(label: l10n.string(.checkoutWilaya), value: wilayaTitle, placeholder: l10n.string(.checkoutSelectWilaya),
                              error: model.fieldErrors[.wilaya].map(message), isActive: picker == .wilaya) {
                open(.wilaya)
            }
            .accessibilityIdentifier("checkout.wilaya")
            TaleedSelectField(label: l10n.string(.checkoutCommune), value: communeTitle,
                              placeholder: l10n.string(.checkoutCommunePlaceholder),
                              helper: communeHelper, error: model.fieldErrors[.commune].map(message), isActive: picker == .commune) {
                if model.communesError != nil { Task { await model.loadCommunes() } }
                open(.commune)
            }
            .disabled(model.form.wilayaId == nil || (model.communes.isEmpty && model.communesError == nil))
            .accessibilityIdentifier("checkout.commune")
            switch model.form.kind {
            case .home:
                TaleedTextArea(label: l10n.string(.checkoutAddressLine), text: addressBinding,
                               placeholder: l10n.string(.checkoutAddressPlaceholder), helper: l10n.string(.appCheckoutAddressHelper),
                               error: fieldError(.addressLine).map(message))
                    .textContentType(.fullStreetAddress)
                    .accessibilityIdentifier("checkout.address")
            case .stopdesk:
                stopdeskField
            }
        }
    }

    @ViewBuilder
    private var stopdeskField: some View {
        let desks = model.desksForCommune
        let noDesk = model.form.communeId != nil && !model.isLoadingStopdesks && model.stopdesksError == nil && desks.isEmpty
        TaleedSelectField(label: l10n.string(.checkoutStopdesk), value: stopdeskTitle, placeholder: l10n.string(.checkoutStopdesk),
                          helper: model.isLoadingStopdesks ? l10n.string(.commonLoading) : nil,
                          error: model.fieldErrors[.stopdesk].map(message)
                              ?? model.stopdesksError.map { l10n.message(for: $0) }
                              ?? (noDesk ? l10n.string(.appCheckoutNoStopdesk) : nil),
                          isActive: picker == .stopdesk) {
            if model.stopdesksError != nil {
                Task { await model.loadStopdesks() }
            } else {
                open(.stopdesk)
            }
        }
        .disabled(model.form.communeId == nil || (desks.isEmpty && model.stopdesksError == nil))
        .accessibilityIdentifier("checkout.stopdesk")
    }

    // MARK: Field values

    private var selectedAddressTitle: String? {
        model.savedAddresses.first { $0.id == model.selectedAddressId }.map(addressTitle)
    }

    func addressTitle(_ address: SavedAddress) -> String {
        // The commune is often part of the street already ("68 rue des Martyrs, Hydra").
        let commune = address.addressLine.localizedCaseInsensitiveContains(address.commune) ? "" : address.commune
        return [address.addressLine, commune, address.wilaya.name].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var wilayaTitle: String? {
        guard let id = model.form.wilayaId else { return nil }
        let name = catalog.catalog?.wilayas.first { $0.id == id }?.name ?? model.pricing?.wilaya.name
        return name.map { "\(id) — \($0)" } ?? String(id)
    }

    private var communeTitle: String? {
        guard let id = model.form.communeId else { return nil }
        return model.communes.first { $0.id == id }?.name
            ?? model.savedAddresses.first { $0.communeId == id }?.commune
    }

    private var communeHelper: String? {
        if model.isLoadingCommunes { return l10n.string(.commonLoading) }
        return model.communesError.map { l10n.message(for: $0) }
    }

    private var stopdeskTitle: String? {
        guard let id = model.form.stopdeskId else { return nil }
        return model.stopdesks.first { $0.id == id }.map(deskTitle)
    }

    func deskTitle(_ desk: StopdeskOption) -> String {
        [desk.name, desk.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
    }

    // MARK: Text fields

    private var recipientBinding: Binding<String> {
        Binding(get: { model.form.recipientName }, set: {
            model.form.recipientName = $0.prefix(utf16Units: CheckoutLimits.recipientNameMax)
            model.edited(.recipientName)
        })
    }

    private var phoneBinding: Binding<String> {
        Binding(get: { model.form.phone }, set: {
            model.form.phone = CheckoutRules.latinDigits($0).prefix(utf16Units: CheckoutLimits.phoneMax)
            model.edited(.phone)
        })
    }

    private var addressBinding: Binding<String> {
        Binding(get: { model.form.addressLine }, set: {
            model.form.addressLine = $0.prefix(utf16Units: CheckoutLimits.addressLineMax)
            model.edited(.addressLine)
        })
    }

    /// The API's refusal, or the device's check once the member has left the field.
    private func fieldError(_ field: CheckoutField) -> CheckoutFieldError? {
        if let error = model.fieldErrors[field] { return error }
        guard leftFields.contains(field) else { return nil }
        switch field {
        case .recipientName: return model.form.recipientNameError
        case .phone: return model.form.phoneError
        default: return nil
        }
    }

    func message(_ error: CheckoutFieldError) -> String {
        switch error {
        case let .nameLength(min, max): l10n.format(.appAuthNameLength, min, max)
        case .phoneInvalid: l10n.string(.appCheckoutPhoneInvalid)
        case .pickAgain: l10n.string(.appSellErrorPickAgain)
        case .invalid: l10n.string(.appCheckoutFieldInvalid)
        }
    }

    /// Opens a picker; the keyboard goes first.
    func open(_ choice: CheckoutPicker) {
        recipientFocused = false
        phoneFocused = false
        picker = choice
    }
}

/// The goods of a bundle checkout (website: the itemized list, then the bundle's price): each item's
/// photo, title and price, then "Lot · 2 articles" and the price.
struct CheckoutBundleCard: View {
    let items: [CheckoutLine]
    let label: String
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            ForEach(items) { item in
                HStack(spacing: TaleedSpacing.s12) {
                    RemoteImage(url: item.imageURL)
                        .frame(width: 40, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: TaleedSize.checkoutThumbRadius, style: .continuous))
                        .accessibilityHidden(true)
                    Text(verbatim: item.title.isolatedByContent)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PriceText(amount: item.price, style: TaleedFont.bodyRegular)
                }
                .accessibilityElement(children: .combine)
            }
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
            HStack {
                Text(label)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PriceText(amount: total, style: TaleedFont.buttonMedium)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(TaleedSpacing.s16)
        .taleedCard()
        .accessibilityIdentifier("checkout.bundle")
    }
}
