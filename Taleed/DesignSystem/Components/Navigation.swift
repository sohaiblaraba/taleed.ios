import SwiftUI

/// A destination of the bottom navigation.
struct BottomNavItem<ID: Hashable>: Identifiable {
    let id: ID
    let icon: TaleedIcon
    let title: String
}

/// Bottom navigation (design-system §5.2, decision D-2): five equal items, the active one in a
/// `blue/50` pill. Place it with `.safeAreaInset(edge: .bottom)`; it draws under the home indicator.
struct BottomNavigation<ID: Hashable>: View {
    let items: [BottomNavItem<ID>]
    @Binding var selection: ID

    var body: some View {
        HStack(spacing: TaleedSize.BottomNav.itemGap) {
            ForEach(items) { item in
                BottomNavButton(item: item, isActive: item.id == selection) { selection = item.id }
            }
        }
        .padding(.top, TaleedSize.BottomNav.paddingTop)
        .padding(.horizontal, TaleedSize.BottomNav.paddingX)
        .padding(.bottom, TaleedSize.BottomNav.paddingBottom)
        .background {
            let shape = UnevenRoundedRectangle(topLeadingRadius: TaleedRadius.l, topTrailingRadius: TaleedRadius.l,
                                               style: .continuous)
            shape
                .fill(TaleedColor.surfacePrimary)
                .overlay(shape.stroke(TaleedColor.borderSubtle, lineWidth: 1))
                .taleedShadow(TaleedElevation.navTop)
                .ignoresSafeArea(edges: .bottom)
        }
        // Labels are 10 pt; past xxxLarge the large content viewer takes over (long press).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
    }
}

private struct BottomNavButton<ID: Hashable>: View {
    let item: BottomNavItem<ID>
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        let color = isActive ? TaleedColor.blue600 : TaleedColor.navy400
        Button(action: action) {
            VStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(item.icon, size: 20, color: color)
                Text(item.title)
                    .taleedFont(isActive ? TaleedFont.navLabelActive : TaleedFont.navLabel)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, TaleedSpacing.s8)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: TaleedSize.BottomNav.itemHeight)
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

/// Bottom sheet chrome (design-system §5.3): handle, heading row with close, content.
struct TaleedBottomSheet<Content: View>: View {
    let title: String
    var onClose: (() -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: TaleedSize.BottomSheet.gap) {
            Capsule()
                .fill(TaleedColor.sheetHandle)
                .frame(width: TaleedSize.BottomSheet.handleWidth, height: TaleedSize.BottomSheet.handleHeight)
                .accessibilityHidden(true)
            HStack {
                Text(title)
                    .taleedFont(SheetStyles.title)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        TaleedIconView(.x, size: 20, color: TaleedColor.textSecondary)
                            .frame(width: 24, height: 24)
                            .minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DesignSystemStrings.string(.commonClose, locale: locale))
                }
            }
            content
        }
        .padding(.top, TaleedSize.BottomSheet.paddingTop)
        .padding(.horizontal, TaleedSize.BottomSheet.paddingX)
        .padding(.bottom, TaleedSize.BottomSheet.paddingBottom)
        .frame(maxWidth: .infinity)
        .background(TaleedColor.surfacePrimary)
    }
}

/// An option of a choice sheet.
struct SheetOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
}

/// The sort sheet: single choice with radios, then "Apply" (blue Primary, decision D-10).
struct SortSheet<ID: Hashable>: View {
    let title: String
    let options: [SheetOption<ID>]
    @State var selection: ID
    let applyTitle: String
    let onApply: (ID) -> Void
    var onClose: (() -> Void)?

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
            TaleedButton(title: applyTitle, kind: .primary, size: .large, isFullWidth: true) { onApply(selection) }
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
            sheet()
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .presentationDetents([.height(height)])
                .presentationCornerRadius(TaleedSize.BottomSheet.topRadius)
                .presentationDragIndicator(.hidden)
                .presentationBackground(TaleedColor.surfacePrimary)
                .environment(\.locale, locale)
                .environment(\.layoutDirection, layoutDirection)
        }
    }
}

/// Centred confirmation for irreversible actions (design-system §5.4).
struct ConfirmationModal: View {
    var icon: TaleedIcon = .trash
    let title: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private static let titleStyle = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                    relativeTo: .subheadline)
    private static let messageStyle = TaleedTextStyle(size: 11, weight: .regular, lineHeight: 15.95, letterSpacing: 0,
                                                      relativeTo: .caption2)

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.Modal.gap) {
            TaleedIconView(icon, size: TaleedSize.Modal.iconSize, color: TaleedColor.feedbackError)
                .frame(width: TaleedSize.Modal.iconCircle, height: TaleedSize.Modal.iconCircle)
                .background(Circle().fill(TaleedColor.errorSoft))
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                Text(title)
                    .taleedFont(Self.titleStyle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .taleedFont(Self.messageStyle)
                    .foregroundStyle(TaleedColor.textBody)
            }
            HStack(spacing: TaleedSize.Modal.actionGap) {
                Button(cancelTitle, action: onCancel)
                    .buttonStyle(TaleedOutlineButtonStyle(height: TaleedSize.Modal.actionHeight, isFullWidth: true))
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(TaleedOutlineButtonStyle(height: TaleedSize.Modal.actionHeight, fill: TaleedColor.feedbackError,
                                                          border: TaleedColor.feedbackError,
                                                          foreground: TaleedColor.textInverse, isFullWidth: true))
            }
        }
        .padding(TaleedSize.Modal.padding)
        .frame(maxWidth: TaleedSize.Modal.width)
        .background(TaleedColor.surfacePrimary, in: RoundedRectangle(cornerRadius: TaleedSize.Modal.radius, style: .continuous))
        .taleedShadow(TaleedElevation.level2)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

extension View {
    /// Shows a confirmation modal over a dim scrim.
    func taleedConfirmation(isPresented: Bool, @ViewBuilder modal: () -> ConfirmationModal) -> some View {
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
