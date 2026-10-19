import SwiftUI

/// Feedback kinds shared by inline alerts and toasts.
enum TaleedFeedbackKind: String, CaseIterable, Sendable {
    case info, success, warning, error
}

/// Inline alert (design-system §2.13): icon · title · short remedy, with an optional link action.
struct InlineAlert: View {
    let kind: TaleedFeedbackKind
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    private static let messageStyle = TaleedTextStyle(size: 11, weight: .regular, lineHeight: 15.4, letterSpacing: 0,
                                                      relativeTo: .caption2)

    var body: some View {
        HStack(alignment: .top, spacing: TaleedSize.alertGap) {
            TaleedIconView(icon, size: TaleedSize.alertIconSize, color: iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                // Title and message read as one element; the link stays its own element.
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .taleedFont(TaleedFont.bodyLarge)
                        .foregroundStyle(TaleedColor.textPrimary)
                    if let message {
                        Text(message)
                            .taleedFont(Self.messageStyle)
                            .foregroundStyle(kind == .info ? TaleedColor.navy700 : TaleedColor.textBody)
                    }
                }
                .accessibilityElement(children: .combine)
                if let actionTitle, let action {
                    TaleedButton(title: actionTitle, kind: .hyperlink, size: .small, action: action)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TaleedSize.alertPadding)
        .background(fill, in: RoundedRectangle(cornerRadius: TaleedSize.alertRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var icon: TaleedIcon {
        switch kind {
        case .info: .info
        case .success: .checkCircle
        case .warning: .warning
        case .error: .warningCircle
        }
    }

    private var iconColor: Color {
        switch kind {
        case .info: TaleedColor.brandPrimary
        case .success: TaleedColor.feedbackSuccess
        case .warning: TaleedColor.warningIcon
        case .error: TaleedColor.feedbackError
        }
    }

    private var fill: Color {
        switch kind {
        case .info: TaleedColor.blue100
        case .success: TaleedColor.successSoft
        case .warning: TaleedColor.warningSoft
        case .error: TaleedColor.errorSoft
        }
    }
}

/// Usage note: a soft-brand info strip (safety tips, short explanations).
struct UsageNote: View {
    let text: String
    var icon: TaleedIcon = .info

    private static let textStyle = TaleedTextStyle(size: 11, weight: .regular, lineHeight: 15.4, letterSpacing: 0,
                                                   relativeTo: .caption2)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TaleedIconView(icon, size: 18, color: TaleedColor.brandPrimary)
            Text(text)
                .taleedFont(Self.textStyle)
                .foregroundStyle(TaleedColor.brandDark)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(TaleedColor.brandSoft, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Toast (design-system §2.14). Light is the component; dark is the "Toast preview" that decision
/// D-11 uses for feedback after an action.
struct TaleedToast: View {
    enum Style: Sendable { case light, dark }

    let kind: TaleedFeedbackKind
    let message: String
    var style: Style = .dark
    var actionTitle: String?
    var onAction: (() -> Void)?
    var onClose: (() -> Void)?
    @Environment(\.locale) private var locale

    private static let darkMessage = TaleedTextStyle(size: 13, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                     relativeTo: .footnote)
    /// "Cancel" on the dark toast: 11/400 mint (§2.14).
    private static let darkAction = TaleedTextStyle(size: 11, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                    relativeTo: .caption2)

    var body: some View {
        HStack(spacing: TaleedSize.toastGap) {
            iconView
            Text(message)
                .taleedFont(style == .light ? TaleedFont.bodyLarge : Self.darkMessage)
                .foregroundStyle(style == .light ? TaleedColor.textPrimary : TaleedColor.textInverse)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let onAction {
                if style == .light {
                    TaleedButton(title: actionTitle, kind: .hyperlink, size: .small, action: onAction)
                } else {
                    Button(action: onAction) {
                        Text(actionTitle)
                            .taleedFont(Self.darkAction)
                            .foregroundStyle(TaleedColor.brandAccent)
                            .frame(minHeight: 32)
                            .minimumHitArea()
                    }
                    .buttonStyle(.plain)
                }
            }
            if let onClose {
                Button(action: onClose) {
                    TaleedIconView(.x, size: TaleedSize.toastIconSize,
                                   color: style == .light ? TaleedColor.navy600 : TaleedColor.navy300)
                        .frame(width: 24, height: 24)
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignSystemStrings.string(.commonClose, locale: locale))
            }
        }
        .padding(TaleedSize.toastPadding)
        .background(style == .light ? TaleedColor.surfacePrimary : TaleedColor.textPrimary,
                    in: RoundedRectangle(cornerRadius: TaleedSize.toastRadius, style: .continuous))
        .taleedShadow(TaleedElevation.level2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var iconView: some View {
        if style == .light {
            TaleedIconView(icon, size: TaleedSize.toastIconSize, color: iconColor)
                .frame(width: TaleedSize.toastIconCircle, height: TaleedSize.toastIconCircle)
                .background(Circle().fill(circleFill))
        } else {
            TaleedIconView(icon, size: 16, color: kind == .success ? TaleedColor.brandAccent : iconColor)
        }
    }

    private var icon: TaleedIcon {
        switch kind {
        case .success: .check
        case .error: .x
        case .warning: .warning
        case .info: .info
        }
    }

    private var iconColor: Color {
        switch kind {
        case .success: TaleedColor.feedbackSuccess
        case .error: TaleedColor.feedbackError
        case .warning: TaleedColor.feedbackWarning
        case .info: style == .light ? TaleedColor.feedbackInfo : TaleedColor.blue300
        }
    }

    private var circleFill: Color {
        switch kind {
        case .success: TaleedColor.successSoft
        case .error: TaleedColor.toastErrorSoft
        case .warning: TaleedColor.toastWarningSoft
        case .info: TaleedColor.toastInfoSoft
        }
    }
}

/// A toast to show.
struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    var kind: TaleedFeedbackKind
    var message: String
    var style: TaleedToast.Style = .dark
    var actionTitle: String?
    var onAction: (() -> Void)?

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool { lhs.id == rhs.id }
}

/// The toasts shown by `.taleedToastHost(_:)`, newest last (Android's `TaleedToastState`). Toasts
/// stack (gap 8, `size.toast.stackGap`); at most `maxVisible` stay on screen: a new toast pushes out
/// the oldest.
@MainActor
@Observable
final class TaleedToastState {
    private(set) var toasts: [ToastItem] = []
    let maxVisible: Int

    init(maxVisible: Int = 3) {
        self.maxVisible = maxVisible
    }

    func show(_ toast: ToastItem) {
        toasts.append(toast)
        if toasts.count > maxVisible { toasts.removeFirst(toasts.count - maxVisible) }
    }

    func dismiss(_ id: ToastItem.ID) {
        toasts.removeAll { $0.id == id }
    }

    func dismissAll() {
        toasts.removeAll()
    }
}

private struct ToastHost: ViewModifier {
    let state: TaleedToastState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            VStack(spacing: TaleedSize.toastStackGap) {
                ForEach(state.toasts) { item in
                    ShownToast(item: item) { state.dismiss(item.id) }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.bottom, TaleedSpacing.s8)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: TaleedMotion.transitionMax), value: state.toasts)
    }
}

/// One toast of the stack: its timer, its announcement and its sideways swipe.
private struct ShownToast: View {
    let item: ToastItem
    let onDismiss: () -> Void
    @State private var dragX: CGFloat = 0
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// 4 s (`motion.toastAutoDismiss`). With VoiceOver the toast stays longer, and one with an action
    /// ("Cancel") stays until it is used or closed, so it can still be reached (Android lengthens it
    /// with the accessibility manager's recommended timeout).
    private var timeout: TimeInterval? {
        guard voiceOver else { return TaleedMotion.toastAutoDismiss }
        return item.actionTitle == nil ? TaleedMotion.toastAutoDismiss * 2.5 : nil
    }

    var body: some View {
        TaleedToast(
            kind: item.kind, message: item.message, style: item.style, actionTitle: item.actionTitle,
            onAction: item.onAction.map { action in { action(); onDismiss() } },
            onClose: onDismiss
        )
        .offset(x: dragX)
        .opacity(1 - min(0.6, Double(abs(dragX)) / 300))
        // A sideways swipe dismisses it, as on Android.
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { dragX = $0.translation.width }
                .onEnded { value in
                    if abs(value.translation.width) > 120 {
                        onDismiss()
                    } else {
                        withAnimation(.easeOut(duration: TaleedMotion.transitionMin)) { dragX = 0 }
                    }
                }
        )
        .task(id: item.id) {
            AccessibilityNotification.Announcement(item.message).post()
            guard let timeout else { return }
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled { onDismiss() }
        }
    }
}

extension View {
    /// Shows the toasts of `state` above the bottom inset, stacked 8 apart (at most three). Each one
    /// dismisses after 4 s (longer with VoiceOver), on a sideways swipe or on ×.
    func taleedToastHost(_ state: TaleedToastState) -> some View {
        modifier(ToastHost(state: state))
    }
}

/// Empty state (design-system §3.5, "Explain · reassure · act"): illustration 84, title 18/400,
/// description 13/400 145 % (max 360 wide), optional Outline Medium action.
struct EmptyState: View {
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var illustration: TaleedImage = .emptyStateSearch
    /// Draws this icon in the 84 pt `brandSoft` circle instead of the illustration.
    var icon: TaleedIcon?

    private static let titleStyle = TaleedTextStyle(size: 18, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                    relativeTo: .body)
    private static let messageStyle = TaleedTextStyle(size: 13, weight: .regular, lineHeight: 18.85, letterSpacing: 0,
                                                      relativeTo: .footnote)

    var body: some View {
        VStack(spacing: TaleedSize.emptyStateGap) {
            artwork
                .frame(width: TaleedSize.emptyStateIllustration, height: TaleedSize.emptyStateIllustration)
                .accessibilityHidden(true)
            Text(title)
                .taleedFont(Self.titleStyle)
                .foregroundStyle(TaleedColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .taleedFont(Self.messageStyle)
                    .foregroundStyle(TaleedColor.textBody)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            if let actionTitle, let action {
                TaleedButton(title: actionTitle, kind: .outline, size: .medium, action: action)
            }
        }
        .padding(TaleedLayout.screenMargin)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var artwork: some View {
        if let icon {
            TaleedIconView(icon, size: TaleedSize.emptyStateIcon, color: TaleedColor.brandPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Circle().fill(TaleedColor.brandSoft))
        } else {
            Image(taleed: illustration).resizable()
        }
    }
}

#Preview("Feedback") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(TaleedFeedbackKind.allCases, id: \.self) { kind in
                InlineAlert(kind: kind, title: "Safety tip", message: "Keep conversations and payments within Taleed.",
                            actionTitle: "Learn more") {}
            }
            TaleedToast(kind: .success, message: "Added to favorites", style: .light, actionTitle: "Cancel",
                        onAction: {}, onClose: {})
            TaleedToast(kind: .success, message: "Added to favorites", actionTitle: "Cancel", onAction: {}, onClose: {})
            EmptyState(title: "No treasures found", message: "Try another city or remove a filter to see more items.",
                       actionTitle: "Clear filters") {}
        }
        .padding()
    }
}
