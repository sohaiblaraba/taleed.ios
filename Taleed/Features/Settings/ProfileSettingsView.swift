import PhotosUI
import SwiftUI

/// "Profil" of Settings (screens.md §7 G16): the website's one card with one Save, as a screen.
///
/// The photo with "Modifier" (the picker; "Chargement…" while it uploads) and "Supprimer la photo", the
/// first and family names (disabled while verified, with the locked hint), the bio, the phone, the
/// wilaya ("16 — Alger", "—" for none), then "Adresse de facturation" (name, address, commune as free
/// text, postal code, wilaya) and "Enregistrer", enabled once something changed.
struct ProfileSettingsView: View {
    @State private var model: ProfileSettingsViewModel
    @State private var picker: ProfilePicker?
    @State private var pickedItem: PhotosPickerItem?
    @State private var showsLibrary = false
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @Environment(CatalogStore.self) private var catalog
    @Environment(SessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(dependencies: SettingsDependencies, store: AccountStore) {
        let uploads = dependencies.uploads
        _model = State(initialValue: ProfileSettingsViewModel(api: dependencies.account, store: store) { data throws(ApiError) in
            try await uploads.upload(data, purpose: .avatar)
        })
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.settingsProfile), onBack: { dismiss() })
        } content: {
            if model.saved != nil {
                form
            } else if let error = model.loadError {
                ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
            } else {
                LoadingStateView()
            }
        }
        // Again once the session is there (a link that opened this screen during launch).
        .task(id: session.user?.id) { await model.loadIfNeeded() }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case .saved: toasts.show(l10n.string(.settingsSaved))
            case let .error(error): toasts.show(error: error)
            }
        }
        .sheet(item: $picker) { picker in
            wilayaSheet(picker).appLanguage(l10n.language)
        }
        .photosPicker(isPresented: $showsLibrary, selection: $pickedItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.photoPicked(data)
                } else {
                    toasts.show(l10n.string(.commonErrorGeneric), kind: .error)
                }
            }
        }
    }

    // MARK: Form

    private var form: some View {
        ScrollViewReader { proxy in
            formContent
                .onChange(of: model.fieldErrorsShown) { _, _ in
                    guard let field = model.firstErrorField else { return }
                    withAnimation { proxy.scrollTo(field, anchor: .top) }
                }
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                photoRow
                    .id(ProfileField.avatar)
                nameFields
                TaleedTextArea(label: l10n.string(.settingsBio), text: text(\.bio, .bio, max: AccountLimits.bioMax),
                               placeholder: l10n.string(.settingsBioPlaceholder), error: message(model.error(.bio)))
                    .accessibilityIdentifier("profile.bio")
                .id(ProfileField.bio)
                TaleedTextField(label: optionalLabel(.settingsPhone), text: text(\.phone, .phone, max: AccountLimits.phoneMax),
                                placeholder: "0550 12 34 56", error: message(model.error(.phone)))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .accessibilityIdentifier("profile.phone")
                .id(ProfileField.phone)
                TaleedSelectField(label: l10n.string(.settingsWilaya), value: wilayaTitle(model.form.wilayaId),
                                  placeholder: l10n.string(.settingsSelectWilaya), error: message(model.error(.wilaya)),
                                  isActive: picker == .wilaya) {
                    picker = .wilaya
                }
                .accessibilityIdentifier("profile.wilaya")
                .id(ProfileField.wilaya)
                billingFields
                TaleedButton(title: l10n.string(.commonSave), kind: .secondary, size: .large, isLoading: model.isSaving,
                             isFullWidth: true) {
                    Task { await model.save() }
                }
                .disabled(!model.canSave)
                .padding(.top, TaleedSpacing.s8)
                .accessibilityIdentifier("profile.save")
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.bottom, TaleedSpacing.s16)
        }
        // The top 16 as a safe-area margin rather than content padding: the same layout at rest, and a
        // field scrolled to for its error stops 16 under the app bar instead of touching its border.
        .safeAreaPadding(.top, TaleedSpacing.s16)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Photo 64, "Photo de profil", "Modifier" and "Supprimer la photo"; at the accessibility sizes the
    /// photo, the label and the buttons stack, so no word breaks.
    @ViewBuilder
    private var photoRow: some View {
        let avatar = TaleedAvatar(initials: TaleedAvatar.initials(from: model.profile?.displayName ?? ""),
                                  size: TaleedSize.avatarXxxl, imageURL: model.avatarURL)
            .accessibilityHidden(true)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                    avatar
                    photoControls(stacked: true)
                }
            } else {
                HStack(spacing: TaleedSpacing.s16) {
                    avatar
                    photoControls(stacked: false)
                }
            }
        }
        .padding(.bottom, TaleedSpacing.s8)
    }

    private func photoControls(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            FieldLabel(text: l10n.string(.settingsAvatar))
            if stacked {
                VStack(alignment: .leading, spacing: TaleedSpacing.s8) { photoButtons }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TaleedSpacing.s8) { photoButtons }
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) { photoButtons }
                }
            }
            if let error = message(model.error(.avatar)) {
                FieldHelper(text: error, color: TaleedColor.feedbackError)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var photoButtons: some View {
        TaleedButton(title: l10n.string(model.isUploading ? .commonLoading : .commonEdit), kind: .outline,
                     size: .small) {
            showsLibrary = true
        }
        .disabled(model.isUploading || model.isSaving)
        .accessibilityLabel("\(l10n.string(.settingsAvatar)), \(l10n.string(.commonEdit))")
        .accessibilityIdentifier("profile.photo")
        if model.hasPhoto {
            TaleedButton(title: l10n.string(.appSettingsAvatarRemove), kind: .hyperlink, size: .small) {
                model.removePhoto()
            }
            .disabled(model.isUploading || model.isSaving)
            .accessibilityIdentifier("profile.removePhoto")
        }
    }

    /// The form's 16 between the two names; the hint 8 under the last one.
    private var nameFields: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) { nameFieldPair }
            let nameError = model.error(.firstName) == .nameLocked
            FieldHelper(text: l10n.string(model.nameLocked || nameError ? .settingsNameLockedHint : .settingsNameHint),
                        color: nameError ? TaleedColor.feedbackError : TaleedColor.textSecondarySmall)
                .accessibilityHidden(false)
        }
    }

    @ViewBuilder
    private var nameFieldPair: some View {
        TaleedTextField(label: l10n.string(.authFirstName),
                        text: text(\.firstName, .firstName, max: AccountLimits.namePartMax),
                        error: model.nameLocked ? nil : message(model.error(.firstName)), showsClearButton: false)
            .textContentType(.givenName)
            .disabled(model.nameLocked)
            .accessibilityIdentifier("profile.firstName")
            .id(ProfileField.firstName)
        TaleedTextField(label: l10n.string(.authLastName),
                        text: text(\.lastName, .lastName, max: AccountLimits.namePartMax),
                        error: model.nameLocked ? nil : message(model.error(.lastName)), showsClearButton: false)
            .textContentType(.familyName)
            .disabled(model.nameLocked)
            .accessibilityIdentifier("profile.lastName")
            .id(ProfileField.lastName)
    }

    private var billingFields: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                SectionTitle(text: l10n.string(.settingsBillingTitle))
                FieldHelper(text: l10n.string(.settingsBillingHint), color: TaleedColor.textSecondarySmall)
                    .accessibilityHidden(false)
            }
            .padding(.top, TaleedSpacing.s16)
            // Empty, the invoice uses the legal name: said in the helper, not as a look-alike placeholder.
            TaleedTextField(label: optionalLabel(.appSettingsBillingNameLabel),
                            text: text(\.billingName, .billingName, max: AccountLimits.billingNameMax),
                            helper: billingNameHelper, error: message(model.error(.billingName)))
                .textContentType(.name)
                .accessibilityIdentifier("profile.billingName")
                .id(ProfileField.billingName)
            TaleedTextField(label: l10n.string(.settingsBillingAddress),
                            text: text(\.billingAddress, .billingAddress, max: AccountLimits.billingAddressMax),
                            error: message(model.error(.billingAddress)))
                .textContentType(.streetAddressLine1)
                .accessibilityIdentifier("profile.billingAddress")
                .id(ProfileField.billingAddress)
            TaleedTextField(label: l10n.string(.settingsBillingCommune),
                            text: text(\.billingCommune, .billingCommune, max: AccountLimits.billingCommuneMax),
                            error: message(model.error(.billingCommune)))
                .textContentType(.addressCity)
                .accessibilityIdentifier("profile.billingCommune")
                .id(ProfileField.billingCommune)
            TaleedTextField(label: optionalLabel(.settingsBillingZip),
                            text: text(\.billingZip, .billingZip, max: AccountLimits.billingZipMax),
                            error: message(model.error(.billingZip)))
                .keyboardType(.numberPad)
                .textContentType(.postalCode)
                .accessibilityIdentifier("profile.billingZip")
                .id(ProfileField.billingZip)
            TaleedSelectField(label: l10n.string(.settingsBillingWilaya), value: wilayaTitle(model.form.billingWilayaId),
                              placeholder: l10n.string(.settingsSelectWilaya), error: message(model.error(.billingWilaya)),
                              isActive: picker == .billingWilaya) {
                picker = .billingWilaya
            }
            .accessibilityIdentifier("profile.billingWilaya")
                .id(ProfileField.billingWilaya)
        }
    }
}

// MARK: - Helpers

extension ProfileSettingsView {
    /// A binding to a text field of the form, kept within its limit; editing clears the field's refusal.
    private func text(_ path: WritableKeyPath<ProfileForm, String>, _ field: ProfileField, max: Int) -> Binding<String> {
        Binding(
            get: { model.form[keyPath: path] },
            set: { value in
                model.form[keyPath: path] = AuthValidation.limited(value, to: max)
                model.edited(field)
            }
        )
    }

    /// "Par défaut : Lina Khelifi" while the billing name is empty.
    private var billingNameHelper: String? {
        let legalName = model.form.legalName.trimmingCharacters(in: .whitespaces)
        guard model.form.billingName.isEmpty, !legalName.isEmpty else { return nil }
        return l10n.format(.appSettingsBillingNameDefault, legalName.isolatedByContent)
    }

    /// "Téléphone (optionnel)".
    private func optionalLabel(_ key: L10nKey) -> String {
        "\(l10n.string(key)) (\(l10n.string(.commonOptional)))"
    }

    /// "16 — Alger"; nil for none (the placeholder shows).
    private func wilayaTitle(_ id: Int?) -> String? {
        guard let id else { return nil }
        let name = catalog.catalog?.wilayas.first { $0.id == id }?.name
        return name.map { "\(id) — \($0)" } ?? String(id)
    }

    private func message(_ error: ProfileFieldError?) -> String? {
        switch error {
        case .nameLength?: l10n.format(.appAuthNameLength, AccountLimits.namePartMin, AccountLimits.namePartMax)
        case .nameLocked?: l10n.string(.settingsNameLockedHint)
        case .phoneInvalid?: l10n.string(.appCheckoutPhoneInvalid)
        case .phoneRefused?: l10n.string(.appSettingsPhoneRefused)
        case .invalid?: l10n.string(.appCheckoutFieldInvalid)
        case nil: nil
        }
    }

    /// The wilayas with "Aucune" first, which removes it (the field then reads "—").
    @ViewBuilder
    private func wilayaSheet(_ picker: ProfilePicker) -> some View {
        let options = [FilterOption(value: "0", title: l10n.string(.appSettingsWilayaNone))] + (catalog.catalog?.wilayas ?? []).map {
            FilterOption(value: String($0.id), title: "\($0.id) — \($0.name)", searchText: String($0.id))
        }
        let current = picker == .wilaya ? model.form.wilayaId : model.form.billingWilayaId
        SellSearchableChoiceSheet(title: l10n.string(picker == .wilaya ? .settingsWilaya : .settingsBillingWilaya),
                                  options: options, selection: String(current ?? 0)) { value in
            let id = Int(value).flatMap { $0 == 0 ? nil : $0 }
            switch picker {
            case .wilaya:
                model.form.wilayaId = id
                model.edited(.wilaya)
            case .billingWilaya:
                model.form.billingWilayaId = id
                model.edited(.billingWilaya)
            }
        }
    }
}

/// The wilaya pickers of the profile form.
enum ProfilePicker: String, Identifiable {
    case wilaya, billingWilaya

    var id: String { rawValue }
}
