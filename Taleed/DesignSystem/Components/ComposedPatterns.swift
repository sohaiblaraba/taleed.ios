import SwiftUI

/// Text settings of the composed patterns (design-system §6) and Item Detail (wireframes.md #4) that
/// have no token.
enum PatternStyles {
    /// Spec row label 13/400 and value 13/600 (Item Detail), saved-search and tip copy 13/400.
    static let body13 = TaleedTextStyle(size: 13, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .footnote)
    static let body13Strong = body13.with(weight: .semibold)
    /// Search results query 13/600.
    static let query = body13Strong
    /// Step intro: "Step 2 of 4" 11/800, title 23/400 (line 29), coaching line 13/400 145 %.
    static let stepLabel = TaleedTextStyle(size: 11, weight: .extrabold, lineHeight: nil, letterSpacing: 0, relativeTo: .caption2)
    static let stepTitle = TaleedTextStyle(size: 23, weight: .regular, lineHeight: 29, letterSpacing: 0, relativeTo: .title2)
    static let stepBody = TaleedTextStyle(size: 13, weight: .regular, lineHeight: 18.85, letterSpacing: 0, relativeTo: .footnote)
}

// MARK: - Search results

/// Search header (§6.2, Android `SearchHeader`): white, padding 0 / 16 / 12, gap 10. The 44 pt bar (`#F7F8FC`,
/// `radius.m`, padding X 12, gap 9) holds back (caret-left on iOS, §1.7; arrow-left on Android), the
/// query 13/600 and clear `x` 17 `#778198`; the filter chips scroll below it.
struct SearchHeader<Filters: View>: View {
    @Binding var text: String
    var placeholder: String
    var onBack: (() -> Void)?
    /// Defaults to "Back" (`common_back`).
    var backAccessibilityLabel: String?
    var onSubmit: () -> Void = {}
    @ViewBuilder let filters: Filters
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                if let onBack {
                    Button(action: onBack) {
                        TaleedIconView(.caretLeft, size: 19, color: TaleedColor.textPrimary).minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(backAccessibilityLabel ?? DesignSystemStrings.string(.commonBack, locale: locale))
                }
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(TaleedColor.textSecondary))
                    .taleedFont(PatternStyles.query)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .tint(TaleedColor.brandPrimary)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(placeholder)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        TaleedIconView(.x, size: 17, color: TaleedColor.textSecondary).minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DesignSystemStrings.string(.commonClear, locale: locale))
                }
            }
            .padding(.horizontal, TaleedSpacing.s12)
            .frame(minHeight: TaleedSize.inputHeight)
            .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            .padding(.horizontal, TaleedLayout.screenMargin)
            filters
        }
        .padding(.bottom, TaleedSpacing.s12)
        .background(TaleedColor.surfacePrimary)
    }
}

extension SearchHeader where Filters == EmptyView {
    init(text: Binding<String>, placeholder: String, onBack: (() -> Void)? = nil, backAccessibilityLabel: String? = nil,
         onSubmit: @escaping () -> Void = {}) {
        self.init(text: text, placeholder: placeholder, onBack: onBack, backAccessibilityLabel: backAccessibilityLabel,
                  onSubmit: onSubmit) { EmptyView() }
    }
}

/// Results summary row (§6.2): "126 items" 13/400 and the sort control ("Newest" 11/400 `#46506A`
/// with `caret-down` 14) that opens the sort sheet (§5.3). Android: `ResultsSummaryRow`.
struct ResultsSummaryRow: View {
    let countLabel: String
    let sortLabel: String
    let onSort: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // From accessibility text sizes on, the sort goes under the count so that neither breaks mid-word.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: TaleedSpacing.s8))
        layout {
            Text(countLabel)
                .taleedFont(PatternStyles.body13)
                .foregroundStyle(TaleedColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onSort) {
                HStack(spacing: TaleedSpacing.s4) {
                    Text(sortLabel)
                        .taleedFont(TaleedFont.meta)
                    TaleedIconView(.caretDown, size: 14, color: nil)
                }
                .foregroundStyle(TaleedColor.textBody)
                .frame(minHeight: TaleedSize.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// Saved-search row (§6.2): `lit.brandSoft`, padding 12, gap 10, `radius.m`; `bell-ringing` 18 and
/// `caret-right` 16 in `brand/primary`, copy 11/400 `lit.brandDark`.
struct SavedSearchRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                TaleedIconView(.bellRinging, size: 18, color: TaleedColor.brandPrimary)
                Text(title)
                    .taleedFont(TaleedFont.meta)
                    .foregroundStyle(TaleedColor.brandDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TaleedIconView(.caretRight, size: 16, color: TaleedColor.brandPrimary)
            }
            .padding(TaleedSpacing.s12)
            .frame(minHeight: TaleedSize.touchTargetMin)
            .background(TaleedColor.brandSoft, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Sell steps

/// Step intro (§6.4, gap 6): the step ("Step 2 of 4" 11/800 `brand/primary`), the title 23/400 and a
/// coaching line 13/400 145 % `#46506A`. Android: `StepIntro`.
struct StepIntro: View {
    let step: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step)
                .taleedFont(PatternStyles.stepLabel)
                .foregroundStyle(TaleedColor.brandPrimary)
            Text(title)
                .taleedFont(PatternStyles.stepTitle)
                .foregroundStyle(TaleedColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .taleedFont(PatternStyles.stepBody)
                .foregroundStyle(TaleedColor.textBody)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Category field of the sell steps (§6.4): grouped fill, `radius.m`, 50 high, padding X 14; a
/// 10/600 `text/secondary` caption ("CATEGORY") over the value 13/400 ("Fashion · Jackets") and
/// `caret-right` 18. Opens the category picker. Android: `CategoryField`.
struct CategoryField: View {
    let label: String
    let value: String
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased(with: locale))
                        .taleedFont(TaleedFont.navLabelActive)
                        .foregroundStyle(TaleedColor.textSecondary)
                    Text(value)
                        .taleedFont(PatternStyles.body13)
                        .foregroundStyle(TaleedColor.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TaleedIconView(.caretRight, size: 18, color: TaleedColor.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 50)
            .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(.isButton)
    }
}

/// Step progress of the sell steps (§6.4, Android `StepProgress`): one 4 pt segment per step, gap 4, `radius.full`; completed and current
/// steps `brand/primary`, upcoming `surface/subtle`. The screen adds the 16 pt side margin.
struct StepProgress: View {
    /// 1-based.
    let current: Int
    var total = 4
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: TaleedSpacing.s4) {
            ForEach(1...max(1, total), id: \.self) { step in
                Capsule()
                    .fill(step <= current ? TaleedColor.brandPrimary : TaleedColor.surfaceSubtle)
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesignSystemStrings.format(.a11yStepProgress, locale: locale, current, total))
    }
}

/// Photo tips card (§6.4): `lit.successSoft`, padding 14, gap 10, `radius.m`; `sparkle` 17
/// `lit.photoTipIcon` #087A59 and a 13/400 title, then tips with 5 pt `feedback/success` dots, gap 8.
struct PhotoTipsCard: View {
    let title: String
    let tips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TaleedIconView(.sparkle, size: 17, color: TaleedColor.photoTipIcon)
                Text(title)
                    .taleedFont(PatternStyles.body13)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                ForEach(tips, id: \.self) { tip in
                    HStack(spacing: TaleedSpacing.s8) {
                        Circle().fill(TaleedColor.feedbackSuccess).frame(width: 5, height: 5)
                        Text(tip)
                            .taleedFont(PatternStyles.body13)
                            .foregroundStyle(TaleedColor.textBody)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaleedColor.successSoft, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Composed patterns") {
    VStack(spacing: 16) {
        StepProgress(current: 2)
        StepIntro(step: "Step 2 of 4", title: "Add photos", message: "Natural light sells better.")
        CategoryField(label: "Category", value: "Fashion · Jackets") {}
        PhotoTipsCard(title: "Photos that sell", tips: ["Natural light", "Plain background", "Show any flaws"])
        ResultsSummaryRow(countLabel: "126 items", sortLabel: "Newest") {}
        SavedSearchRow(title: "Notify me about new listings") {}
        SpecRow(label: "Brand", value: "Shein")
        SpecRow(label: "Condition") { ConditionTag(.veryGood) }
        HStack {
            PageCountPill(current: 1, total: 4)
            PageDots(count: 4, current: 0).padding(8).background(.gray)
        }
        Spacer()
        ItemDetailActionBar(makeOfferLabel: "Make an offer", onMakeOffer: {}, buyNowLabel: "Buy now", onBuyNow: {})
    }
    .padding(.horizontal)
}
