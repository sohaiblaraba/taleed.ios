import SwiftUI
import UIKit

/// A destination of the bottom navigation.
struct BottomNavItem<ID: Hashable>: Identifiable {
    let id: ID
    let icon: TaleedIcon
    let title: String
}

/// Bottom navigation (design-system §5.2, decision D-2): five equal items, the active one in a
/// `blue/50` pill. Place it with `.safeAreaInset(edge: .bottom)`; it draws under the home indicator.
struct TaleedBottomNavigation<ID: Hashable>: View {
    let items: [BottomNavItem<ID>]
    @Binding var selection: ID
    /// True when the bar sits inside another bottom bar (Item Detail's action bar), which then draws
    /// the fill, top corners and shadow (Android's `embedded`).
    var isEmbedded = false
    @State private var barWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Labels are 10 pt; past xxxLarge the large content viewer takes over (long press).
    private static var maxTypeSize: DynamicTypeSize { .xxxLarge }

    var body: some View {
        let metrics = labelMetrics
        HStack(spacing: TaleedSize.bottomNavItemGap) {
            ForEach(items) { item in
                BottomNavButton(item: item, isActive: item.id == selection, labelScale: metrics.scale,
                                paddingX: metrics.paddingX) { selection = item.id }
            }
        }
        .padding(.top, TaleedSize.bottomNavPaddingTop)
        .padding(.horizontal, TaleedSize.bottomNavPaddingX)
        .padding(.bottom, TaleedSize.bottomNavPaddingBottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        .background {
            if !isEmbedded {
                let shape = UnevenRoundedRectangle(topLeadingRadius: TaleedRadius.l, topTrailingRadius: TaleedRadius.l,
                                                   style: .continuous)
                shape
                    .fill(TaleedColor.surfacePrimary)
                    .overlay(shape.stroke(TaleedColor.borderSubtle, lineWidth: 1))
                    .taleedShadow(TaleedElevation.navTop)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .dynamicTypeSize(...Self.maxTypeSize)
        .accessibilityElement(children: .contain)
    }

    /// One label size for all five items (item padding 8 / 16, §5.2): the widest label (in the active weight) sets a shared
    /// scale, so no label shrinks alone and none truncates. The item padding is 16 (§5.2) when the
    /// labels fit, and gives way to the label first.
    private var labelMetrics: (scale: CGFloat, paddingX: CGFloat) {
        let preferred = TaleedSpacing.s16
        guard barWidth > 0, !items.isEmpty else { return (1, preferred) }
        let count = CGFloat(items.count)
        let itemWidth = (barWidth - 2 * TaleedSize.bottomNavPaddingX - (count - 1) * TaleedSize.bottomNavItemGap) / count
        let size = min(dynamicTypeSize, Self.maxTypeSize)
        let font = TaleedFont.navLabelActive.uiFont(sizeCategory: UIContentSizeCategory(size))
        let widest = items.map { ceil(($0.title as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        guard widest > 0 else { return (1, preferred) }
        let minimumPadding: CGFloat = 2
        let paddingX = min(preferred, max(minimumPadding, (itemWidth - widest) / 2))
        let scale = min(1, (itemWidth - 2 * paddingX) / widest)
        return (scale, paddingX)
    }
}

private struct BottomNavButton<ID: Hashable>: View {
    let item: BottomNavItem<ID>
    let isActive: Bool
    let labelScale: CGFloat
    let paddingX: CGFloat
    let action: () -> Void

    var body: some View {
        let color = isActive ? TaleedColor.blue600 : TaleedColor.navy400
        let style = isActive ? TaleedFont.navLabelActive : TaleedFont.navLabel
        Button(action: action) {
            VStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(item.icon, size: 20, color: color)
                Text(item.title)
                    .taleedFont(TaleedTextStyle(size: style.size * labelScale, weight: style.weight,
                                                lineHeight: nil, letterSpacing: 0, relativeTo: style.relativeTo))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, TaleedSpacing.s8)
            .padding(.horizontal, paddingX)
            .frame(maxWidth: .infinity, minHeight: TaleedSize.bottomNavItemHeight)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous).fill(TaleedColor.blue50)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            TaleedIconView(item.icon, size: 20, color: nil)
            Text(item.title)
        }
    }
}

private enum SheetStyles {
    static let title = TaleedTextStyle(size: 18, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .body)
    static let option = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .subheadline)
}

/// Bottom sheet chrome (design-system §5.3): the 40 x 4 handle, a heading row with the start-aligned
/// title and close, then the content (gap 18, padding 10 / 22 / 22). Present it with `.taleedSheet`.
struct TaleedBottomSheet<Content: View>: View {
    let title: String
    /// Defaults to the sheet title, 18/400. The sign-in sheet uses Title 2, as on Android.
    var titleStyle: TaleedTextStyle?
    var onClose: (() -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: TaleedSize.bottomSheetGap) {
            Capsule()
                .fill(TaleedColor.sheetHandle)
                .frame(width: TaleedSize.bottomSheetHandleWidth, height: TaleedSize.bottomSheetHandleHeight)
                .accessibilityHidden(true)
            HStack {
                Text(title)
                    .taleedFont(titleStyle ?? SheetStyles.title)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onClose {
                    Button(action: onClose) {
                        TaleedIconView(.x, size: 20, color: TaleedColor.textSecondary)
                            .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DesignSystemStrings.string(.commonClose, locale: locale))
                }
            }
            content
        }
        .padding(.top, TaleedSize.bottomSheetPaddingTop)
        .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
        .padding(.bottom, TaleedSize.bottomSheetPaddingBottom)
        .frame(maxWidth: .infinity)
        .background(TaleedColor.surfacePrimary)
    }
}

/// An option of a choice sheet.
struct SheetOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
}

/// Sort sheet content (design-system §5.3): heading row with close, single choice with the radio
/// component, then a full-width blue Primary "Apply" (decision D-10). Android: `SortSheetContent`.
struct SortSheetContent<ID: Hashable>: View {
    let title: String
    let options: [SheetOption<ID>]
    @Binding var selection: ID
    let onApply: () -> Void
    let onClose: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        TaleedBottomSheet(title: title, onClose: onClose) {
            VStack(spacing: 0) {
                ForEach(options) { option in
                    let isSelected = option.id == selection
                    Button { selection = option.id } label: {
                        HStack {
                            Text(option.title)
                                .taleedFont(isSelected ? SheetStyles.option.with(weight: .semibold) : SheetStyles.option)
                                .foregroundStyle(TaleedColor.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            RadioIndicator(isSelected: isSelected)
                        }
                        .frame(minHeight: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            TaleedButton(title: DesignSystemStrings.string(.commonApply, locale: locale), kind: .primary, size: .large,
                         isFullWidth: true, action: onApply)
        }
    }
}

extension View {
    /// The sort sheet as a bottom sheet over the scrim (Android's `SortBottomSheet`): drag down or tap
    /// outside to dismiss, "Apply" commits.
    func sortBottomSheet<ID: Hashable>(isPresented: Binding<Bool>, title: String, options: [SheetOption<ID>],
                                       selection: Binding<ID>, onApply: @escaping () -> Void) -> some View {
        taleedSheet(isPresented: isPresented) {
            SortSheetContent(title: title, options: options, selection: selection,
                             onApply: { onApply(); isPresented.wrappedValue = false },
                             onClose: { isPresented.wrappedValue = false })
        }
    }
}

extension View {
    /// Presents a bottom sheet sized to its content, in the presenter's language and direction.
    func taleedSheet<Sheet: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(TaleedSheetPresenter(isPresented: isPresented, sheet: content))
    }
}

private struct TaleedSheetPresenter<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheet: () -> Sheet
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            // Sized to the content (24 pt top corners, the design-system handle instead of the system
            // one); taller content (large text) gets the full height and scrolls.
            ScrollView {
                sheet()
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .presentationDetents([.height(height)])
            .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
            .presentationDragIndicator(.hidden)
            .presentationBackground(TaleedColor.surfacePrimary)
            .environment(\.locale, locale)
            .environment(\.layoutDirection, layoutDirection)
        }
    }
}

/// Confirmation modal card (design-system §5.4): icon circle (`errorSoft` + trash), title, message,
/// "Cancel" (Outline) and the destructive action (Danger), equal widths. Use only for irreversible
/// confirmations. From accessibility sizes on, the actions stack, the destructive one first, so no
/// label breaks mid-word (Android's `ConfirmationModalCard`).
struct ConfirmationModalCard: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    /// Defaults to "Cancel" (`common_cancel`).
    var cancelTitle: String?
    var icon: TaleedIcon = .trash
    /// Draws the destructive action pressed, for the design-system gallery.
    var forcesConfirmPressed = false
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let titleStyle = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                    relativeTo: .subheadline)
    private static let messageStyle = TaleedTextStyle(size: 11, weight: .regular, lineHeight: 15.95, letterSpacing: 0,
                                                      relativeTo: .caption2)

    var body: some View {
        // One stack, gap 14 between the icon circle, title, message and actions (§5.4).
        VStack(alignment: .leading, spacing: TaleedSize.modalGap) {
            TaleedIconView(icon, size: TaleedSize.modalIconSize, color: TaleedColor.feedbackError)
                .frame(width: TaleedSize.modalIconCircle, height: TaleedSize.modalIconCircle)
                .background(Circle().fill(TaleedColor.errorSoft))
                .accessibilityHidden(true)
            Text(title)
                .taleedFont(Self.titleStyle)
                .foregroundStyle(TaleedColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .taleedFont(Self.messageStyle)
                .foregroundStyle(TaleedColor.textBody)
            if dynamicTypeSize >= .accessibility1 {
                VStack(spacing: TaleedSize.modalActionGap) {
                    confirmButton
                    cancelButton
                }
            } else {
                HStack(spacing: TaleedSize.modalActionGap) {
                    cancelButton
                    confirmButton
                }
            }
        }
        .padding(TaleedSize.modalPadding)
        .frame(maxWidth: TaleedSize.modalWidth)
        .background(TaleedColor.surfacePrimary, in: RoundedRectangle(cornerRadius: TaleedSize.modalRadius, style: .continuous))
        .taleedShadow(TaleedElevation.level2)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var cancelButton: some View {
        TaleedButton(title: cancelTitle ?? DesignSystemStrings.string(.commonCancel, locale: locale), kind: .outline,
                     size: .medium, isFullWidth: true, metrics: .modalAction, action: onCancel)
    }

    private var confirmButton: some View {
        TaleedButton(title: confirmTitle, kind: .danger, size: .medium, isFullWidth: true,
                     forcedState: forcesConfirmPressed ? .pressed : nil, metrics: .modalAction, action: onConfirm)
    }
}

extension View {
    /// Shows a confirmation modal over a dim scrim.
    func taleedConfirmation(isPresented: Bool, @ViewBuilder modal: () -> ConfirmationModalCard) -> some View {
        overlay {
            if isPresented {
                ZStack {
                    TaleedColor.textPrimary.opacity(0.5)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    modal().padding(TaleedLayout.screenMargin)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: isPresented)
    }
}
