import SwiftUI
import UIKit

/// The Sell tab (screens.md §1.1, §2 G7): the brand app bar and the page heading of Figma "Sell an
/// Item", then the form. Signed out: the sign-in prompt (§0.5). A new form for each member who signs in.
struct SellView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(\.sellDependencies) private var dependencies
    @Environment(CatalogStore.self) private var catalog
    @Environment(ExploreReferenceStore.self) private var references
    @State private var model: SellViewModel?

    var body: some View {
        ShellScreen {
            ShellBrandAppBar()
        } content: {
            if session.isSignedIn, let model {
                SellFormView(model: model)
            } else {
                VStack(spacing: 0) {
                    PageHeading(eyebrow: l10n.string(.tabSell), title: l10n.string(.sellTitle))
                    if session.isSignedIn {
                        LoadingStateView()
                    } else {
                        SignInPromptView()
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
}

/// The form of Figma "Sell an Item" (wireframes.md #2): photos, title, description, category and
/// subcategory, brand, size, condition, price, shipping wilaya, "Publier l'annonce".
private struct SellFormView: View {
    @Bindable var model: SellViewModel
    private static let topID = "sell.top"
    @State private var picker: SellPicker?
    @FocusState private var titleFocused: Bool
    @FocusState private var sizeFocused: Bool
    @FocusState private var priceFocused: Bool
    @Environment(LanguageManager.self) private var l10n
    @Environment(CatalogStore.self) private var catalog
    @Environment(ExploreReferenceStore.self) private var references
    @Environment(SessionManager.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    PageHeading(eyebrow: l10n.string(.tabSell), title: l10n.string(.sellTitle))
                        .id(Self.topID)
                    if let catalog = catalog.catalog {
                        form(catalog)
                    } else if let error = catalog.error {
                        ErrorStateView(error: error) { Task { await catalog.refresh() } }
                            .frame(minHeight: 320)
                    } else {
                        LoadingStateView().frame(minHeight: 320)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.resets) { _, _ in proxy.scrollTo(Self.topID, anchor: .top) }
            .onChange(of: model.refusals) { _, _ in
                guard let field = model.firstErrorField else { return }
                dismissKeyboard()
                withAnimation(.easeInOut(duration: TaleedMotion.transitionMax)) { proxy.scrollTo(field, anchor: .top) }
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
        TaleedTextField(label: l10n.string(.sellTitleLabel),
                        text: Binding(get: { model.form.title }, set: { model.form.title = SellForm.cappedTitle($0) }),
                        placeholder: l10n.string(.sellTitlePlaceholder),
                        error: model.fieldErrors[.title].map(message(for:)),
                        focus: $titleFocused)
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier("sell.title")
    }

    private var descriptionField: some View {
        TaleedTextArea(label: l10n.string(.sellDescriptionLabel),
                       text: Binding(get: { model.form.description },
                                     set: { model.form.description = SellForm.cappedDescription($0) }),
                       placeholder: l10n.string(.sellDescriptionPlaceholder),
                       helper: l10n.string(.appSellDescriptionHint),
                       error: model.fieldErrors[.description].map(message(for:)))
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier("sell.description")
    }

    /// Category, then its subcategory (disabled until a category is chosen), gap 8 (wireframes.md 5.4).
    private func categoryFields(_ catalog: Catalog) -> some View {
        let parent = catalog.categories.first { $0.id == model.form.parentCategoryId }
        let child = parent?.children.first { $0.id == model.form.categoryId }
        return VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
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
        TaleedTextField(label: l10n.string(.sellPriceLabel),
                        text: Binding(get: { model.form.priceText }, set: { model.form.priceText = FilterDraft.priceText($0) }),
                        placeholder: "0",
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
            if let error = model.publishError {
                InlineAlert(kind: .error, title: l10n.message(for: error))
                    .accessibilityIdentifier("sell.publishError")
            }
            TaleedButton(title: l10n.string(model.isPublishing ? .sellPublishing : .sellPublish),
                         kind: .secondary, size: .large, isFullWidth: true) {
                Task { await publish() }
            }
            .disabled(!model.canPublish)
            .accessibilityIdentifier("sell.publish")
        }
    }

    // MARK: Pickers

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

    private func publish() async {
        dismissKeyboard()
        guard let listingId = await model.publish() else { return }
        toasts.show(l10n.string(.sellPublished))
        model.reset(wilayaId: session.user?.wilayaId)
        router.push(.listing(id: listingId))
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
