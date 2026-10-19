import SwiftUI

/// Text settings of the composed patterns (design-system §6) and Item Detail (wireframes.md #4) that
/// have no token.
enum PatternStyles {
    /// Spec row label 13/400 and value 13/600 (Item Detail), saved-search and tip copy 13/400.
    static let body13 = TaleedTextStyle(size: 13, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .footnote)
    static let body13Strong = body13.with(weight: .semibold)
    /// Search results query 13/600.
    static let query = body13Strong
}

// MARK: - Item Detail

/// Sticky bottom bar of Item Detail (wireframes.md #4.17, `size.bottomActionBar`): white, top corners
/// `radius.l`, `elevation.navTop`; the actions row has padding 12 / 16 / 8 / 16 and gap 8, and every
/// action grows from its own width ("Make an offer" Tertiary + "Buy now" Secondary render 180 / 220
/// on 440). `footer` takes the bottom navigation drawn without its own background.
struct BottomActionBar<Actions: View, Footer: View>: View {
    @ViewBuilder let actions: Actions
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            GrowRow(spacing: TaleedSize.BottomActionBar.gap) { actions }
                .padding(.top, TaleedSize.BottomActionBar.paddingTop)
                .padding(.horizontal, TaleedSize.BottomActionBar.paddingX)
                .padding(.bottom, TaleedSize.BottomActionBar.paddingBottom)
            footer
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: TaleedRadius.l, topTrailingRadius: TaleedRadius.l, style: .continuous)
                .fill(TaleedColor.surfacePrimary)
                .taleedShadow(TaleedElevation.navTop)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
    }
}

extension BottomActionBar where Footer == EmptyView {
    init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
        self.footer = EmptyView()
    }
}

/// Item Detail's two decision actions: Tertiary "Make an offer" and Secondary "Buy now", Large.
struct ItemDetailActions: View {
    let offerTitle: String
    let buyTitle: String
    let onOffer: () -> Void
    let onBuy: () -> Void

    var body: some View {
        TaleedButton(title: offerTitle, kind: .tertiary, size: .large, isFullWidth: true, action: onOffer)
        TaleedButton(title: buyTitle, kind: .secondary, size: .large, isFullWidth: true, action: onBuy)
    }
}

/// A row whose children share the width like CSS flex-grow 1: each gets its own width plus an equal
/// share of what is left. When they do not fit, each gets a share in proportion to its width (labels
/// then wrap). Mirrors in right-to-left layouts.
struct GrowRow: Layout {
    var spacing: CGFloat = TaleedSpacing.s8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(total: proposal.width, subviews: subviews)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        let width = proposal.width ?? widths.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var leading = bounds.minX
        for (subview, width) in zip(subviews, widths(total: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: leading, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            leading += width + spacing
        }
    }

    private func widths(total: CGFloat?, subviews: Subviews) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let total, !ideal.isEmpty else { return ideal }
        let available = max(0, total - spacing * CGFloat(subviews.count - 1))
        let sum = ideal.reduce(0, +)
        if sum <= available {
            let extra = (available - sum) / CGFloat(ideal.count)
            return ideal.map { $0 + extra }
        }
        return ideal.map { sum > 0 ? available * $0 / sum : available / CGFloat(ideal.count) }
    }
}

/// Item Detail spec row (wireframes.md #4.6): label 13/400 `text/secondary`, value 13/600
/// `text/primary` (a link in `blue/600`), space-between, padding 14 / 16, at least 44 high (50 with a
/// condition tag), 1 pt `border/subtle` bottom border except on the last row.
struct SpecRow<Value: View>: View {
    let label: String
    var showsDivider = true
    var action: (() -> Void)?
    @ViewBuilder let value: Value

    var body: some View {
        let row = HStack(spacing: TaleedSpacing.s16) {
            Text(label)
                .taleedFont(PatternStyles.body13)
                .foregroundStyle(TaleedColor.textSecondary)
            Spacer(minLength: 0)
            value
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, TaleedSpacing.s16)
        .frame(minHeight: TaleedSize.touchTargetMin)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
        }
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isLink)
        } else {
            row.accessibilityElement(children: .combine)
        }
    }
}

extension SpecRow where Value == SpecValueText {
    /// A text value; with an action the value is a link ("Women › Clothes").
    init(label: String, value: String, showsDivider: Bool = true, action: (() -> Void)? = nil) {
        self.label = label
        self.showsDivider = showsDivider
        self.action = action
        self.value = SpecValueText(text: value, isLink: action != nil)
    }
}

/// The value of a spec row: 13/600, `text/primary` or `blue/600` for a link.
struct SpecValueText: View {
    let text: String
    var isLink = false

    var body: some View {
        Text(verbatim: text)
            .taleedFont(PatternStyles.body13Strong)
            .foregroundStyle(isLink ? TaleedColor.blue600 : TaleedColor.textPrimary)
    }
}

/// Photo position pill on a gallery (§6.3): "1 / 4", 11/600 white on `#11182D` 80 %, padding 5 / 10.
/// Digits read left to right in every language.
struct PhotoCountPill: View {
    /// 1-based.
    let index: Int
    let count: Int
    @Environment(\.locale) private var locale

    var body: some View {
        Text(verbatim: "\(index) / \(count)".isolatedLeftToRight)
            .taleedFont(TaleedFont.tagLabel)
            .foregroundStyle(TaleedColor.textInverse)
            .monospacedDigit()
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(Capsule().fill(TaleedColor.scrim))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DesignSystemStrings.format(.a11yPhotoPosition, locale: locale, index, count))
    }
}

/// Page dots on the Item Detail image hero: active 8 white, inactive 6 white at 50 %, gap 6.
struct PhotoPageDots: View {
    let count: Int
    /// 0-based.
    let current: Int
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                let isActive = index == current
                Circle()
                    .fill(TaleedColor.textInverse.opacity(isActive ? 1 : 0.5))
                    .frame(width: isActive ? 8 : 6, height: isActive ? 8 : 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesignSystemStrings.format(.a11yPhotoPosition, locale: locale, current + 1, count))
    }
}

// MARK: - Search results

/// Search results header (§6.2): white, padding 0 / 16 / 12, gap 10. The 44 pt bar (`#F7F8FC`,
/// `radius.m`, padding X 12, gap 9) holds back (caret-left on iOS, §1.7; arrow-left on Android), the
/// query 13/600 and clear `x` 17 `#778198`; the filter chips scroll below it.
struct SearchResultsHeader<Filters: View>: View {
    @Binding var text: String
    var placeholder: String
    var onBack: (() -> Void)?
    var backAccessibilityLabel: String = ""
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
                    .accessibilityLabel(backAccessibilityLabel)
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
                    .accessibilityLabel(DesignSystemStrings.string(.a11yClearText, locale: locale))
                }
            }
            .padding(.horizontal, TaleedSpacing.s12)
            .frame(minHeight: TaleedSize.Input.height)
            .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            .padding(.horizontal, TaleedLayout.screenMargin)
            filters
        }
        .padding(.bottom, TaleedSpacing.s12)
        .background(TaleedColor.surfacePrimary)
    }
}

extension SearchResultsHeader where Filters == EmptyView {
    init(text: Binding<String>, placeholder: String, onBack: (() -> Void)? = nil, backAccessibilityLabel: String = "",
         onSubmit: @escaping () -> Void = {}) {
        self.init(text: text, placeholder: placeholder, onBack: onBack, backAccessibilityLabel: backAccessibilityLabel,
                  onSubmit: onSubmit) { EmptyView() }
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

/// Sell-step progress (§6.4): one 4 pt segment per step, gap 4, `radius.full`; completed and current
/// steps `brand/primary`, upcoming `surface/subtle`. The screen adds the 16 pt side margin.
struct SellStepProgress: View {
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
        SellStepProgress(current: 2)
        PhotoTipsCard(title: "Photos that sell", tips: ["Natural light", "Plain background", "Show any flaws"])
        SavedSearchRow(title: "Notify me about new listings") {}
        SpecRow(label: "Brand", value: "Shein")
        SpecRow(label: "Condition") { ConditionTag(.veryGood) }
        HStack {
            PhotoCountPill(index: 1, count: 4)
            PhotoPageDots(count: 4, current: 0).padding(8).background(.gray)
        }
        Spacer()
        BottomActionBar {
            ItemDetailActions(offerTitle: "Make an offer", buyTitle: "Buy now", onOffer: {}, onBuy: {})
        }
    }
    .padding(.horizontal)
}
