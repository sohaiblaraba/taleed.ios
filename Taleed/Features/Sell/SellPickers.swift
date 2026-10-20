import SwiftUI

/// The choice lists of the sell form. Short lists (category, subcategory, condition) open in a bottom
/// sheet sized to them; long ones (wilaya, brand) in a full-height sheet with a search field
/// (design-system §2.5: a select opens a picker, §5.3: sheets for choices). Picking closes the sheet.
enum SellPicker: String, Identifiable, Hashable, Sendable {
    case category, subcategory, condition, brand, wilaya

    var id: String { rawValue }

    /// Opens full height, with a search field.
    var isLong: Bool { self == .brand || self == .wilaya }
}

/// The sheet's heading (design-system §5.3): the handle, the start-aligned title and close.
struct SellSheetHeader: View {
    let title: String
    let onClose: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSize.bottomSheetGap) {
            Capsule()
                .fill(TaleedColor.sheetHandle)
                .frame(width: TaleedSize.bottomSheetHandleWidth, height: TaleedSize.bottomSheetHandleHeight)
                .accessibilityHidden(true)
            HStack {
                Text(title)
                    .taleedFont(TaleedTextStyle(size: 18, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .body))
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    TaleedIconView(.x, size: 20, color: TaleedColor.textSecondary)
                        .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.string(.commonClose))
            }
        }
        .padding(.top, TaleedSize.bottomSheetPaddingTop)
        .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
        .padding(.bottom, TaleedSpacing.s8)
    }
}

/// A short list in a content-sized bottom sheet: the rows, a check on the current choice.
struct SellChoiceSheet: View {
    let title: String
    let options: [FilterOption]
    let selection: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SellSheetHeader(title: title) { dismiss() }
            VStack(spacing: 0) {
                ForEach(options) { option in
                    FilterOptionRow(option: option, isSelected: option.value == selection, inset: TaleedSize.bottomSheetPaddingX) {
                        if let value = option.value { onSelect(value) }
                        dismiss()
                    }
                    .accessibilityIdentifier("sell.option.\(option.id)")
                }
            }
            .padding(.bottom, TaleedSpacing.s16)
        }
        .background(TaleedColor.surfacePrimary)
    }
}

/// A long list (the 58 wilayas) in a full-height sheet with a search field that also matches codes. A
/// short one (a wilaya with few communes) opens half height, without the search field.
struct SellSearchableChoiceSheet: View {
    let title: String
    let options: [FilterOption]
    let selection: String?
    let onSelect: (String) -> Void
    @State private var searchText = ""
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    /// Under this many options, the list needs no search and no full height.
    static let searchThreshold = 8

    private var isShort: Bool { options.count < Self.searchThreshold }

    var body: some View {
        VStack(spacing: 0) {
            SellSheetHeader(title: title) { dismiss() }
            if !isShort {
                TaleedTextField(text: $searchText, placeholder: l10n.string(.commonSearch), leadingIcon: .magnifyingGlass)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
                    .padding(.bottom, TaleedSpacing.s12)
                    .accessibilityIdentifier("sell.search")
            }
            let shown = options.filter { $0.matches(searchText) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { option in
                            FilterOptionRow(option: option, isSelected: option.value == selection,
                                            inset: TaleedSize.bottomSheetPaddingX) {
                                if let value = option.value { onSelect(value) }
                                dismiss()
                            }
                        }
                        if shown.isEmpty {
                            Text(l10n.string(.filtersNoResults))
                                .taleedFont(TaleedFont.bodyRegular)
                                .foregroundStyle(TaleedColor.textBody)
                                .multilineTextAlignment(.center)
                                .padding(TaleedSpacing.s24)
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                // Opens on the current choice ("25 — Constantine"), not at the top of the list.
                .onAppear {
                    if let selection { proxy.scrollTo(selection, anchor: .center) }
                }
            }
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .presentationDetents(isShort ? [.medium, .large] : [.large])
        .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
        .presentationDragIndicator(.hidden)
        .presentationBackground(TaleedColor.surfacePrimary)
    }
}

/// The brand picker: the website's combobox as a full-height sheet. A search field (60 characters at
/// most), "Sans marque / Autre" while it is empty, the catalog brands that match, and "Utiliser « … »"
/// when the text names no catalog brand (screens.md §7 G7). A typed name that matches a brand,
/// ignoring case, picks that brand.
struct SellBrandSheet: View {
    let selection: SellBrand
    let onSelect: (SellBrand) -> Void
    @State private var query = ""
    @Environment(ExploreReferenceStore.self) private var references
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    private var brands: [CatalogBrand] { references.brands.value ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            SellSheetHeader(title: l10n.string(.sellBrandLabel)) { dismiss() }
            TaleedTextField(text: queryBinding, placeholder: l10n.string(.sellBrandSearchPlaceholder),
                            leadingIcon: .magnifyingGlass)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(pickTyped)
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.bottom, TaleedSpacing.s12)
                .accessibilityIdentifier("sell.brandSearch")
            ScrollView {
                LazyVStack(spacing: 0) {
                    rows
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .task { await references.loadBrands() }
        .presentationDetents([.large])
        .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
        .presentationDragIndicator(.hidden)
        .presentationBackground(TaleedColor.surfacePrimary)
    }

    private var queryBinding: Binding<String> {
        Binding(get: { query }, set: { query = SellForm.cappedBrandSearch($0) })
    }

    private var isTyping: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    @ViewBuilder
    private var rows: some View {
        if SellBrand.offersTypedName(query, brands: brands), let typed = SellBrand.choice(forTyped: query, brands: brands),
           let name = typed.displayName {
            UseTypedBrandRow(title: l10n.format(.sellBrandCustom, name.isolatedByContent)) { pick(typed) }
        }
        if !isTyping {
            FilterOptionRow(option: FilterOption(value: "", title: l10n.string(.sellNoBrand)),
                            isSelected: selection == .none) { pick(.none) }
                .accessibilityIdentifier("sell.noBrand")
        }
        ForEach(SellBrand.matches(query, in: brands)) { brand in
            FilterOptionRow(option: FilterOption(value: brand.id, title: brand.name),
                            isSelected: selection == .catalog(brand)) { pick(.catalog(brand)) }
        }
        if references.brands.value == nil {
            if let error = references.brands.error {
                InlineAlert(kind: .error, title: l10n.message(for: error), actionTitle: l10n.string(.commonRetry)) {
                    Task { await references.loadBrands() }
                }
                .padding(TaleedLayout.screenMargin)
            } else {
                ProgressView()
                    .tint(TaleedColor.brandPrimary)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .accessibilityLabel(l10n.string(.commonLoading))
            }
        }
    }

    /// Return on the keyboard takes the typed text (a catalog brand of that name, or the name).
    private func pickTyped() {
        guard let choice = SellBrand.choice(forTyped: query, brands: brands) else { return }
        pick(choice)
    }

    private func pick(_ brand: SellBrand) {
        onSelect(brand)
        dismiss()
    }
}

/// "Utiliser « … »": a plus, then the typed name, as the website's last combobox row.
private struct UseTypedBrandRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: TaleedSpacing.s12) {
                    TaleedIconView(.plus, size: 20, color: TaleedColor.brandPrimary)
                    Text(verbatim: title)
                        .taleedFont(TaleedFont.bodyLarge.with(weight: .semibold))
                        .foregroundStyle(TaleedColor.brandPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, TaleedSpacing.s12)
                .padding(.horizontal, TaleedLayout.screenMargin)
                .frame(maxWidth: .infinity, minHeight: 56)
                Rectangle()
                    .fill(TaleedColor.borderSubtle)
                    .frame(height: 1)
                    .padding(.leading, TaleedLayout.screenMargin)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sell.useTypedBrand")
    }
}
