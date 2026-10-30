import SwiftUI

/// "Adresses enregistrées" (screens.md §2 G16 item 9; an app feature, the website has none, so the copy
/// is the app's): what they are for, each address as a card (the recipient with "Par défaut", the phone,
/// the address, "commune, wilaya") with "Modifier", "Définir par défaut" and "Supprimer", then "Ajouter
/// une adresse" (at 10, why not). Loading, the error with Retry (offline included), the empty state and
/// pull-to-refresh.
struct AddressesView: View {
    @State private var model: AddressesViewModel
    /// The form: nil closed; `.new` or an address to edit.
    @State private var formTarget: AddressFormTarget?
    @State private var pendingDelete: SavedAddress?
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    private let api: AddressesApi

    init(api: AddressesApi) {
        self.api = api
        _model = State(initialValue: AddressesViewModel(api: api))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.appSettingsAddressesTitle), onBack: { dismiss() })
        } content: {
            if let addresses = model.addresses {
                list(addresses)
            } else if let error = model.loadError {
                ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
            } else {
                LoadingStateView()
            }
        }
        .task { await model.loadIfNeeded() }
        // The legal name and the phone prefill a new address.
        .task { await account.loadIfNeeded() }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case .deleted: toasts.show(l10n.string(.appSettingsAddressDeleted))
            case let .error(error): toasts.show(error: error)
            }
        }
        .sheet(item: $formTarget) { target in
            AddressFormSheet(api: api, target: target, isFirst: model.addresses?.isEmpty ?? true,
                             recipientName: account.profile.map { "\($0.firstName) \($0.lastName)" },
                             phone: account.profile?.phone) { _ in
                formTarget = nil
                toasts.show(l10n.string(target.address == nil ? .appCheckoutAddressSaved : .appSettingsAddressUpdated))
                Task { await model.saved() }
            }
            .appLanguage(l10n.language)
            // A sheet here, a screen on Android: logged on both (plan/analytics-screens.md).
            .analyticsScreen(.addressForm)
        }
        .taleedConfirmation(isPresented: pendingDelete != nil) {
            ConfirmationModalCard(title: l10n.string(.appSettingsAddressDeleteTitle),
                                  message: l10n.string(.appSettingsAddressDeleteBody),
                                  confirmTitle: l10n.string(.commonDelete),
                                  onConfirm: confirmDelete,
                                  onCancel: { pendingDelete = nil })
        }
    }

    private func list(_ addresses: [SavedAddress]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                if addresses.isEmpty {
                    EmptyState(title: l10n.string(.appSettingsAddressesEmpty), message: l10n.string(.appSettingsAddressesHint),
                               icon: .mapPin)
                        .frame(maxWidth: .infinity)
                        .padding(.top, TaleedSpacing.s32)
                        .accessibilityIdentifier("addresses.empty")
                    // The list's own "Ajouter une adresse", so the action looks the same in both states.
                    addButton
                } else {
                    Text(l10n.string(.appSettingsAddressesHint))
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(addresses) { address in
                        AddressCard(address: address, isBusy: model.busyIds.contains(address.id),
                                    onEdit: { formTarget = .edit(address) },
                                    onMakeDefault: { Task { await model.makeDefault(id: address.id) } },
                                    onDelete: { pendingDelete = address })
                    }
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        addButton
                        if !model.canAdd {
                            FieldHelper(text: l10n.string(.appErrorAddressLimit), color: TaleedColor.textSecondarySmall)
                                .accessibilityHidden(false)
                        }
                    }
                }
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.vertical, TaleedSpacing.s16)
        }
        .refreshable { await model.reload() }
    }

    private var addButton: some View {
        TaleedButton(title: l10n.string(.appSettingsAddressAdd), kind: .tertiary, size: .large, leadingIcon: .plus,
                     isFullWidth: true) {
            formTarget = .new
        }
        .disabled(!model.canAdd)
        .accessibilityIdentifier("addresses.add")
    }

    private func confirmDelete() {
        guard let address = pendingDelete else { return }
        pendingDelete = nil
        Task { await model.delete(id: address.id) }
    }
}

/// What the address form opens on.
enum AddressFormTarget: Identifiable {
    case new
    case edit(SavedAddress)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(address): address.id
        }
    }

    var address: SavedAddress? {
        if case let .edit(address) = self { return address }
        return nil
    }
}

/// One saved address.
private struct AddressCard: View {
    let address: SavedAddress
    let isBusy: Bool
    let onEdit: () -> Void
    let onMakeDefault: () -> Void
    let onDelete: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                // At the accessibility sizes the badge takes its own line above the name.
                if dynamicTypeSize.isAccessibilitySize {
                    defaultBadge
                    recipient
                } else {
                    HStack(spacing: TaleedSpacing.s8) {
                        recipient
                        defaultBadge
                    }
                }
                Text(verbatim: address.phone.isolatedLeftToRight)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                Text(address.addressLine)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(address.commune), \(address.wilaya.name)")
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                if address.communeId == nil {
                    FieldHelper(text: l10n.string(.appSettingsAddressCommuneAgain), color: TaleedColor.warningText)
                        .accessibilityHidden(false)
                }
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TaleedSpacing.s8) { actions }
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) { actions }
            }
            .disabled(isBusy)
        }
        .padding(TaleedSpacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .taleedCard()
        .accessibilityIdentifier("addresses.card.\(address.id)")
    }

    private var recipient: some View {
        Text(address.recipientName)
            .taleedFont(TaleedFont.sectionTitle)
            .foregroundStyle(TaleedColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var defaultBadge: some View {
        if address.isDefault {
            TaleedBadge(title: l10n.string(.appSettingsAddressDefault), tone: .success, icon: .checkCircle)
        }
    }

    @ViewBuilder
    private var actions: some View {
        TaleedButton(title: l10n.string(.commonEdit), kind: .outline, size: .small, action: onEdit)
            .accessibilityIdentifier("addresses.edit.\(address.id)")
        if !address.isDefault {
            TaleedButton(title: l10n.string(.appSettingsAddressMakeDefault), kind: .outline, size: .small, action: onMakeDefault)
                .accessibilityIdentifier("addresses.default.\(address.id)")
        }
        TaleedButton(title: l10n.string(.commonDelete), kind: .hyperlink, size: .small, action: onDelete)
            .accessibilityIdentifier("addresses.delete.\(address.id)")
    }
}

/// The address form, full height: the recipient, the phone, the wilaya and its commune (searchable
/// lists), the address, the default switch and "Enregistrer".
private struct AddressFormSheet: View {
    @State private var model: AddressFormViewModel
    @State private var picker: AddressPicker?
    let onSaved: (SavedAddress) -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    init(api: AddressesApi, target: AddressFormTarget, isFirst: Bool, recipientName: String?, phone: String?,
         onSaved: @escaping (SavedAddress) -> Void) {
        _model = State(initialValue: AddressFormViewModel(api: api, editing: target.address, isFirst: isFirst,
                                                          recipientName: recipientName, phone: phone))
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            SellSheetHeader(title: l10n.string(model.editing == nil ? .appSettingsAddressAdd : .appSettingsAddressEditTitle)) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                    TaleedTextField(label: l10n.string(.checkoutRecipientName),
                                    text: text(\.recipientName, .recipientName, max: AccountLimits.recipientNameMax),
                                    error: message(model.error(.recipientName)))
                        .textContentType(.name)
                        .accessibilityIdentifier("address.recipient")
                    TaleedTextField(label: l10n.string(.checkoutPhone), text: text(\.phone, .phone, max: CheckoutLimits.phoneMax),
                                    placeholder: "0550 12 34 56", helper: l10n.string(.checkoutPhoneHint),
                                    error: message(model.error(.phone)))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .accessibilityIdentifier("address.phone")
                    TaleedSelectField(label: l10n.string(.checkoutWilaya), value: wilayaTitle,
                                      placeholder: l10n.string(.settingsSelectWilaya), error: message(model.error(.wilaya)),
                                      isActive: picker == .wilaya) {
                        picker = .wilaya
                    }
                    .accessibilityIdentifier("address.wilaya")
                    communeField
                    TaleedTextField(label: l10n.string(.checkoutAddressLine),
                                    text: text(\.addressLine, .addressLine, max: AccountLimits.addressLineMax),
                                    placeholder: l10n.string(.checkoutAddressPlaceholder),
                                    error: model.error(.addressLine) == .required
                                        ? l10n.string(.appSettingsAddressLineRequired) : message(model.error(.addressLine)))
                        .textContentType(.fullStreetAddress)
                        .accessibilityIdentifier("address.line")
                    if model.showsDefaultSwitch {
                        Toggle(isOn: $model.form.isDefault) { Text(l10n.string(.appSettingsAddressDefaultToggle)) }
                            .toggleStyle(.taleedCheckbox)
                            .accessibilityIdentifier("address.default")
                    }
                    TaleedButton(title: l10n.string(.commonSave), kind: .secondary, size: .large, isLoading: model.isSending,
                                 isFullWidth: true, action: save)
                        .disabled(!model.canSave)
                        .accessibilityIdentifier("address.save")
                }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.vertical, TaleedSpacing.s16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(TaleedColor.surfaceElevated.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(model.isSending)
        .task { await model.loadIfNeeded() }
        .onChange(of: model.notice) { _, error in
            guard let error else { return }
            model.notice = nil
            toasts.show(error: error)
        }
        .sheet(item: $picker) { picker in
            pickerSheet(picker).appLanguage(l10n.language)
        }
    }

    @ViewBuilder
    private var communeField: some View {
        let commune = model.form.communeId.flatMap { id in model.communes.first { $0.id == id }?.name }
            ?? (model.form.communeId != nil ? model.editing?.commune : nil)
        TaleedSelectField(label: l10n.string(.checkoutCommune), value: commune,
                          placeholder: l10n.string(.checkoutCommunePlaceholder),
                          error: model.communesError.map { l10n.message(for: $0) } ?? message(model.error(.commune)),
                          isActive: picker == .commune) {
            if model.communesError != nil {
                Task { await model.retryCommunes() }
            } else {
                picker = .commune
            }
        }
        .disabled(model.form.wilayaId == nil || model.isLoadingCommunes)
        .accessibilityIdentifier("address.commune")
    }

    private var wilayaTitle: String? {
        guard let id = model.form.wilayaId else { return nil }
        let name = catalog.catalog?.wilayas.first { $0.id == id }?.name ?? model.editing?.wilaya.name
        return name.map { "\(id) — \($0)" } ?? String(id)
    }

    @ViewBuilder
    private func pickerSheet(_ picker: AddressPicker) -> some View {
        switch picker {
        case .wilaya:
            SellSearchableChoiceSheet(
                title: l10n.string(.checkoutWilaya),
                options: (catalog.catalog?.wilayas ?? []).map {
                    FilterOption(value: String($0.id), title: "\($0.id) — \($0.name)", searchText: String($0.id))
                },
                selection: model.form.wilayaId.map(String.init)
            ) { value in
                if let id = Int(value) { Task { await model.selectWilaya(id) } }
            }
        case .commune:
            SellSearchableChoiceSheet(title: l10n.string(.checkoutCommune),
                                      options: model.communes.map { FilterOption(value: String($0.id), title: $0.name) },
                                      selection: model.form.communeId.map(String.init)) { value in
                if let id = Int(value) { model.selectCommune(id) }
            }
        }
    }

    private func text(_ path: WritableKeyPath<AddressForm, String>, _ field: AddressField, max: Int) -> Binding<String> {
        Binding(
            get: { model.form[keyPath: path] },
            set: { value in
                model.form[keyPath: path] = AuthValidation.limited(value, to: max)
                model.edited(field)
            }
        )
    }

    private func message(_ error: AddressFieldError?) -> String? {
        switch error {
        case .nameLength?: l10n.format(.appAuthNameLength, AccountLimits.recipientNameMin, AccountLimits.recipientNameMax)
        case .phoneInvalid?: l10n.string(.appCheckoutPhoneInvalid)
        case .required?: l10n.string(.appCheckoutFieldInvalid)
        case .communeAgain?: l10n.string(.appSettingsAddressCommuneAgain)
        case .invalid?: l10n.string(.appCheckoutFieldInvalid)
        case nil: nil
        }
    }

    private func save() {
        Task {
            if let address = await model.save() { onSaved(address) }
        }
    }
}

private enum AddressPicker: String, Identifiable {
    case wilaya, commune

    var id: String { rawValue }
}
