import SwiftUI
import UIKit

/// The form of Figma "Sell an Item" (wireframes.md #2): photos, title, description, category and
/// subcategory, brand, size, condition, price, shipping wilaya, "Publier l'annonce". The edit form
/// (G8) is the same without the page heading, its button "Enregistrer les modifications".
struct SellFormView: View {
    @Bindable var model: SellViewModel
    /// The Sell tab's "SELL / Vendre un article" heading; the edit form has its title in the app bar.
    var showsHeading = true
    var submitTitle: L10nKey = .sellPublish
    /// A notice above the button (the edit form: the listing was reloaded).
    var notice: String?
    /// Publish or save; the field errors are the model's.
    let onSubmit: () async -> Void

    init(model: SellViewModel, showsHeading: Bool = true, submitTitle: L10nKey = .sellPublish, notice: String? = nil,
         onSubmit: @escaping () async -> Void) {
        _model = Bindable(model)
        self.showsHeading = showsHeading
        self.submitTitle = submitTitle
        self.notice = notice
        self.onSubmit = onSubmit
    }
    private static let topID = "sell.top"
    private static let submitID = "sell.submit"
    @State private var picker: SellPicker?
    @FocusState private var titleFocused: Bool
    @FocusState private var sizeFocused: Bool
    @FocusState private var priceFocused: Bool
    @Environment(LanguageManager.self) private var l10n
    @Environment(CatalogStore.self) private var catalog
    @Environment(ExploreReferenceStore.self) private var references

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if showsHeading {
                        PageHeading(eyebrow: l10n.string(.tabSell), title: l10n.string(.sellTitle))
                            .id(Self.topID)
                    } else {
                        Color.clear.frame(height: 0).id(Self.topID)
                    }
                    if let catalog = catalog.catalog {
                        form(catalog)
                    } else if let error = catalog.error {
                        ErrorStateView(error: error) { Task { await catalog.refresh() } }
                            .frame(minHeight: 320)
                    } else {
                        LoadingStateView().frame(minHeight: 320)
                    }
                    // The end of the form, under the button's bottom margin (kept clear of the tab bar).
                    Color.clear.frame(height: 0).id(Self.submitID)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.resets) { _, _ in proxy.scrollTo(Self.topID, anchor: .top) }
            .onChange(of: model.refusals) { _, _ in
                guard let field = model.firstErrorField else { return }
                dismissKeyboard()
                withAnimation(.easeInOut(duration: TaleedMotion.transitionMax)) { proxy.scrollTo(field, anchor: .top) }
            }
            // A failed publish or save with no field to fix: the alert and the button, to retry.
            .onChange(of: model.publishError) { _, error in
                guard error != nil, model.firstErrorField == nil else { return }
                withAnimation(.easeInOut(duration: TaleedMotion.transitionMax)) {
                    proxy.scrollTo(Self.submitID, anchor: .bottom)
                }
            }
        }
        // The number pad has no Return key: "OK" puts the keyboard away (and shows the button again).
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if priceFocused || sizeFocused {
                    Spacer()
                    Button(l10n.string(.appKeyboardDone)) { dismissKeyboard() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("sell.keyboardDone")
                }
            }
        }
        .task {
            if catalog.catalog == nil, !catalog.isRefreshing { await catalog.refresh() }
            await references.loadSizes()
        }
        .taleedSheet(isPresented: shortPickerBinding) { shortPicker }
        .sheet(item: longPickerBinding) { picker in
            longPicker(picker).appLanguage(l10n.language)
        }
    }

    // MARK: Form

    private func form(_ catalog: Catalog) -> some View {
        VStack(alignment: .leading, spacing: TaleedLayout.formFieldGap) {
            SellPhotosSection(model: model).id(SellField.photos)
            titleField.id(SellField.title)
            descriptionField.id(SellField.description)
            categoryFields(catalog)
            brandField.id(SellField.brand)
            sizeField.id(SellField.size)
            conditionField(catalog).id(SellField.condition)
            priceField.id(SellField.price)
            wilayaField(catalog).id(SellField.wilaya)
            publishSection
        }
        .padding(.top, TaleedLayout.formBodyPaddingTop)
        .padding(.horizontal, TaleedLayout.formBodyPaddingX)
        .padding(.bottom, TaleedLayout.formBodyPaddingBottom)
        // The fields keep their look while the listing is sent, but take no edits.
        .allowsHitTesting(!model.isPublishing)
    }

    private var titleField: some View {
        // Wraps over up to 3 lines, so a long title can be read back; Return still ends editing.
        TaleedTextField(label: l10n.string(.sellTitleLabel),
                        text: $model.form.title,
                        placeholder: l10n.string(.sellTitlePlaceholder),
                        error: model.fieldErrors[.title].map(message(for:)),
                        focus: $titleFocused,
                        lineLimit: 1...3,
                        maxLength: SellLimits.titleMax,
                        counter: model.form.title.fieldCounter(max: SellLimits.titleMax))
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier("sell.title")
    }

    private var descriptionField: some View {
        TaleedTextArea(label: l10n.string(.sellDescriptionLabel),
                       text: Binding(get: { model.form.description },
                                     set: { model.form.description = SellForm.cappedDescription($0) }),
                       placeholder: l10n.string(.sellDescriptionPlaceholder),
                       helper: l10n.string(.appSellDescriptionHint),
                       error: model.fieldErrors[.description].map(message(for:)),
                       counter: model.form.description.fieldCounter(max: SellLimits.descriptionMax))
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier("sell.description")
    }

    /// Category, then its subcategory (disabled until a category is chosen), gap 8 (wireframes.md 5.4).
    private func categoryFields(_ catalog: Catalog) -> some View {
        let parent = catalog.categories.first { $0.id == model.form.parentCategoryId }
        let child = parent?.children.first { $0.id == model.form.categoryId }
        // The category's error keeps the subcategory's label at a distance, so it reads as the category's.
        let spacing = model.fieldErrors[.category] == nil ? TaleedSpacing.s8 : TaleedSpacing.s16
        return VStack(alignment: .leading, spacing: spacing) {
            TaleedSelectField(label: l10n.string(.sellCategoryLabel), value: parent?.name,
                              placeholder: l10n.string(.sellSelectCategory),
                              error: model.fieldErrors[.category].map(message(for:)), isActive: picker == .category) {
                open(.category)
            }
            .accessibilityIdentifier("sell.category")
            .id(SellField.category)
            TaleedSelectField(label: l10n.string(.sellSubcategoryLabel), value: child?.name,
                              placeholder: l10n.string(parent == nil ? .sellSelectCategoryFirst : .sellSelectSubcategory),
                              error: model.fieldErrors[.subcategory].map(message(for:)), isActive: picker == .subcategory) {
                open(.subcategory)
            }
            .disabled(parent == nil)
            .accessibilityIdentifier("sell.subcategory")
            .id(SellField.subcategory)
        }
    }

    private var brandField: some View {
        TaleedSelectField(label: optionalLabel(.sellBrandLabel), value: model.form.brand.displayName,
                          placeholder: l10n.string(.sellSelectBrand),
                          error: model.fieldErrors[.brand].map(message(for:)), isActive: picker == .brand) {
            open(.brand)
        }
        .accessibilityIdentifier("sell.brand")
    }

    /// Free text (30 characters at most) with the sizes on sale as suggestions while it is focused.
    private var sizeField: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            TaleedTextField(label: optionalLabel(.sellSizeLabel),
                            text: Binding(get: { model.form.size }, set: { model.form.size = SellForm.cappedSize($0) }),
                            placeholder: l10n.string(.sellSizePlaceholder),
                            error: model.fieldErrors[.size].map(message(for:)),
                            focus: $sizeFocused)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityIdentifier("sell.size")
            let suggestions = SellSizeSuggestions.matching(model.form.size, in: references.sizes.value ?? [])
            if sizeFocused, !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TaleedLayout.chipRowGap) {
                        ForEach(suggestions, id: \.self) { size in
                            CategoryChip(title: size) { model.form.size = SellForm.cappedSize(size) }
                        }
                    }
                    .padding(.vertical, 7)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(l10n.string(.appSellSizeSuggestions))
            }
        }
    }

    private func conditionField(_ catalog: Catalog) -> some View {
        TaleedSelectField(label: l10n.string(.sellConditionLabel), value: catalog.condition(model.form.condition)?.label,
                          placeholder: l10n.string(.sellSelectCondition),
                          error: model.fieldErrors[.condition].map(message(for:)), isActive: picker == .condition) {
            open(.condition)
        }
        .accessibilityIdentifier("sell.condition")
    }

    private var priceField: some View {
        // The Money icon of the Figma specimen; the digits grouped as prices are ("3 000") while not
        // being typed.
        TaleedTextField(label: l10n.string(.sellPriceLabel),
                        text: Binding(get: { priceFocused ? model.form.priceText : groupedPrice },
                                      set: { model.form.priceText = FilterDraft.priceText($0) }),
                        placeholder: "0",
                        leadingIcon: .money,
                        helper: l10n.string(.sellPriceHint),
                        error: model.fieldErrors[.price].map(message(for:)),
                        focus: $priceFocused)
            .keyboardType(.numberPad)
            .accessibilityIdentifier("sell.price")
    }

    private func wilayaField(_ catalog: Catalog) -> some View {
        TaleedSelectField(label: l10n.string(.sellWilayaLabel),
                          value: catalog.wilaya(model.form.wilayaId).map(Self.wilayaLabel),
                          placeholder: l10n.string(.sellSelectWilaya),
                          helper: l10n.string(.sellWilayaHint),
                          error: model.fieldErrors[.wilaya].map(message(for:)), isActive: picker == .wilaya) {
            open(.wilaya)
        }
        .accessibilityIdentifier("sell.wilaya")
    }

    /// "16 — Alger", as the website's select.
    private static func wilayaLabel(_ wilaya: CatalogWilaya) -> String { "\(wilaya.id) — \(wilaya.name)" }

    private var publishSection: some View {
        VStack(spacing: TaleedSpacing.s12) {
            if let notice {
                InlineAlert(kind: .warning, title: notice)
                    .accessibilityIdentifier("sell.notice")
            }
            if let error = model.publishError {
                // "No connection" over its remedy, as the design system's alert (§2.13).
                InlineAlert(kind: .error, title: l10n.string(ErrorStateView.titleKey(for: error)),
                            message: ErrorStateView.message(for: error, l10n: l10n))
                    .accessibilityIdentifier("sell.publishError")
            }
            TaleedButton(title: l10n.string(submitButtonTitle), kind: .secondary, size: .large,
                         isLoading: model.isPublishing, isFullWidth: true, keepsLabelWhileLoading: true) {
                Task { await submit() }
            }
            // The edit form saves once something differs from the listing as loaded.
            .disabled(!model.canPublish || !model.hasEdits)
            .accessibilityIdentifier("sell.publish")
        }
    }

    /// "Publication…" while publishing, "Enregistrement…" while the edit form saves.
    private var submitButtonTitle: L10nKey {
        guard model.isPublishing else { return submitTitle }
        return model.isEditing ? .appSellSaving : .sellPublishing
    }

    /// The price with its digits grouped ("3 000"; "3.000" in Arabic), as prices show.
    private var groupedPrice: String {
        model.form.price.map { PriceFormatter.number($0, language: l10n.language) } ?? model.form.priceText
    }

    // MARK: Publishing

    /// Opens a picker; the keyboard goes, so that focus does not come back to a field when it closes.
    private func open(_ choice: SellPicker) {
        dismissKeyboard()
        picker = choice
    }

    private func dismissKeyboard() {
        titleFocused = false
        sizeFocused = false
        priceFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func submit() async {
        dismissKeyboard()
        await onSubmit()
    }

    // MARK: Text

    /// "Marque (optionnel)", as the website's label with its muted "(optionnel)" (Figma "Brand (optional)").
    private func optionalLabel(_ key: L10nKey) -> String {
        "\(l10n.string(key)) (\(l10n.string(.commonOptional)))"
    }

    private func message(for error: SellFieldError) -> String {
        SellMessages.text(for: error, language: l10n.language)
    }
}

// MARK: - Pickers

extension SellFormView {
    private var shortPickerBinding: Binding<Bool> {
        Binding(get: { picker.map { !$0.isLong } ?? false }, set: { if !$0, picker?.isLong == false { picker = nil } })
    }

    private var longPickerBinding: Binding<SellPicker?> {
        Binding(get: { picker?.isLong == true ? picker : nil }, set: { if $0 == nil, picker?.isLong == true { picker = nil } })
    }

    @ViewBuilder
    private var shortPicker: some View {
        let catalog = catalog.catalog
        switch picker {
        case .category:
            SellChoiceSheet(title: l10n.string(.sellCategoryLabel),
                            options: (catalog?.categories ?? []).map { FilterOption(value: $0.id, title: $0.name) },
                            selection: model.form.parentCategoryId) { model.form.selectParentCategory($0) }
        case .subcategory:
            let parent = catalog?.categories.first { $0.id == model.form.parentCategoryId }
            SellChoiceSheet(title: l10n.string(.sellSubcategoryLabel),
                            options: (parent?.children ?? []).map { FilterOption(value: $0.id, title: $0.name) },
                            selection: model.form.categoryId) { model.form.categoryId = $0 }
        case .condition:
            SellChoiceSheet(title: l10n.string(.sellConditionLabel),
                            options: (catalog?.conditions ?? []).filter { SellLimits.isSendableCondition($0.value) }
                                .map { FilterOption(value: $0.value, title: $0.label) },
                            selection: model.form.condition) { model.form.condition = $0 }
        case .brand, .wilaya, nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func longPicker(_ picker: SellPicker) -> some View {
        switch picker {
        case .brand:
            SellBrandSheet(selection: model.form.brand) { model.form.brand = $0 }
        case .wilaya:
            SellSearchableChoiceSheet(
                title: l10n.string(.sellWilayaLabel),
                options: (catalog.catalog?.wilayas ?? []).map {
                    FilterOption(value: String($0.id), title: Self.wilayaLabel($0), searchText: String($0.id))
                },
                selection: model.form.wilayaId.map(String.init)
            ) { model.form.wilayaId = Int($0) }
        case .category, .subcategory, .condition:
            EmptyView()
        }
    }
}
