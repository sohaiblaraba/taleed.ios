import Observation
import SwiftUI

/// Draws the confirmation modal (design-system §5.4) over the whole window: the dim scrim covers the
/// tab bar too and takes every touch, so the member answers with one of the two buttons (screens.md
/// §0.9: centered modals are only for irreversible confirmations). The shell owns one and puts it in
/// the environment; `taleedConfirmation` hands its modal to it. Without a host (a sheet, a screen
/// shown outside the shell), the modal draws over the view that asks for it.
@MainActor
@Observable
final class ConfirmationHost {
    struct Presentation {
        /// The `taleedConfirmation` that shows the modal: only it can take the modal away.
        let owner: UUID
        /// The tab whose screen asked for it: it shows only while that tab does (a link that opens
        /// another tab hides it; back on the tab, it shows again).
        let tab: AppTab?
        let modal: ConfirmationModalCard
        let order: Int
    }

    private var presentations: [UUID: Presentation] = [:]
    private var counter = 0

    /// The modal to show while `tab` is on screen: the latest one asked for there.
    func presentation(in tab: AppTab?) -> Presentation? {
        presentations.values.filter { $0.tab == nil || $0.tab == tab }.max { $0.order < $1.order }
    }

    func present(_ modal: ConfirmationModalCard, owner: UUID, tab: AppTab?) {
        let order = presentations[owner]?.order ?? { counter += 1; return counter }()
        presentations[owner] = Presentation(owner: owner, tab: tab, modal: modal, order: order)
    }

    func dismiss(owner: UUID) {
        presentations[owner] = nil
    }
}

private struct ConfirmationHostKey: EnvironmentKey {
    static var defaultValue: ConfirmationHost? { nil }
}

extension EnvironmentValues {
    /// The window's confirmation host (set by the shell; nil inside sheets).
    var confirmationHost: ConfirmationHost? {
        get { self[ConfirmationHostKey.self] }
        set { self[ConfirmationHostKey.self] = newValue }
    }
}

extension View {
    /// Shows a confirmation modal over a dim scrim: over the whole window inside the shell (tab bar
    /// included, nothing else takes a touch), over this view elsewhere.
    func taleedConfirmation(isPresented: Bool, @ViewBuilder modal: () -> ConfirmationModalCard) -> some View {
        modifier(TaleedConfirmationPresenter(isPresented: isPresented, modal: modal()))
    }

    /// Draws the host's modal for the tab on screen over this view (the shell, above its tab bar).
    func confirmationHostOverlay(_ host: ConfirmationHost, tab: AppTab?) -> some View {
        overlay {
            if let presentation = host.presentation(in: tab) {
                ConfirmationScrim(modal: presentation.modal)
            }
        }
        .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: host.presentation(in: tab)?.owner)
    }
}

/// The dim scrim and the centered modal. Taps on the scrim do nothing; VoiceOver's escape gesture
/// cancels, as the Cancel button.
private struct ConfirmationScrim: View {
    let modal: ConfirmationModalCard

    var body: some View {
        ZStack {
            TaleedColor.modalDim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)
            modal
                .padding(TaleedLayout.screenMargin)
                .accessibilityAction(.escape) { modal.onCancel() }
        }
        .transition(.opacity)
        .accessibilityIdentifier("confirmation.scrim")
    }
}

private struct TaleedConfirmationPresenter: ViewModifier {
    let isPresented: Bool
    let modal: ConfirmationModalCard
    @Environment(\.confirmationHost) private var host
    @Environment(\.shellTab) private var tab
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        if let host {
            content
                .onAppear { sync(host) }
                .onChange(of: isPresented) { sync(host) }
                // The text can change while the modal shows (the language): the host gets the new one.
                .onChange(of: [modal.title, modal.message, modal.confirmTitle]) { sync(host) }
                // The screen left (a link opened another one): the modal goes with it, and comes back with it.
                .onDisappear { host.dismiss(owner: owner) }
        } else {
            content
                .overlay {
                    if isPresented { ConfirmationScrim(modal: modal) }
                }
                .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: isPresented)
        }
    }

    private func sync(_ host: ConfirmationHost) {
        if isPresented {
            host.present(modal, owner: owner, tab: tab)
        } else {
            host.dismiss(owner: owner)
        }
    }
}

/// The kind of action a confirmation modal asks for.
enum ConfirmationTone: Sendable {
    /// Irreversible and destructive (delete, block): Danger, the design-system default.
    case destructive
    /// Binding but not destructive (accept an offer).
    case positive
}

/// Confirmation modal card (design-system §5.4): icon circle (`errorSoft` + trash), title, message,
/// "Cancel" (Outline) and the destructive action (Danger), equal widths. Use only for irreversible
/// confirmations. When a label would not fit its half on one line (accessibility sizes, or a long
/// label such as "Générer et télécharger"), the actions stack, the main one first, so the pair never
/// looks unbalanced (Android's `ConfirmationModalCard`). `footnote`: a muted aside under the message.
struct ConfirmationModalCard: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    /// Defaults to "Cancel" (`common_cancel`).
    var cancelTitle: String?
    var icon: TaleedIcon = .trash
    /// `.positive` for a confirmation that is not destructive (accepting an offer): the icon on
    /// `brandSoft` and a Primary action instead of Danger.
    var tone: ConfirmationTone = .destructive
    /// Draws the destructive action pressed, for the design-system gallery.
    var forcesConfirmPressed = false
    /// Background detail under the message, muted (who the label names as the sender).
    var footnote: String?
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The width the two actions share, once measured.
    @State private var actionsWidth: CGFloat = 0

    private static let titleStyle = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                    relativeTo: .subheadline)
    private static let messageStyle = TaleedTextStyle(size: 11, weight: .regular, lineHeight: 15.95, letterSpacing: 0,
                                                      relativeTo: .caption2)

    var body: some View {
        // One stack, gap 14 between the icon circle, title, message and actions (§5.4).
        VStack(alignment: .leading, spacing: TaleedSize.modalGap) {
            TaleedIconView(icon, size: TaleedSize.modalIconSize,
                           color: tone == .positive ? TaleedColor.brandPrimary : TaleedColor.feedbackError)
                .frame(width: TaleedSize.modalIconCircle, height: TaleedSize.modalIconCircle)
                .background(Circle().fill(tone == .positive ? TaleedColor.brandSoft : TaleedColor.errorSoft))
                .accessibilityHidden(true)
            Text(title)
                .taleedFont(Self.titleStyle)
                .foregroundStyle(TaleedColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .taleedFont(Self.messageStyle)
                .foregroundStyle(TaleedColor.textBody)
            if let footnote {
                Text(footnote)
                    .taleedFont(Self.messageStyle)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
            }
            Group {
                if stacksActions {
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
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionsWidth = $0 }
        }
        .padding(TaleedSize.modalPadding)
        .frame(maxWidth: TaleedSize.modalWidth)
        .background(TaleedColor.surfaceElevated, in: RoundedRectangle(cornerRadius: TaleedSize.modalRadius, style: .continuous))
        .taleedShadow(TaleedElevation.level2)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var resolvedCancelTitle: String {
        cancelTitle ?? DesignSystemStrings.string(.commonCancel, locale: locale)
    }

    /// Stacked from accessibility sizes on, or when a label is wider than its half of the row.
    private var stacksActions: Bool {
        if dynamicTypeSize >= .accessibility1 { return true }
        let metrics = TaleedButtonMetrics.modalAction
        let width = actionsWidth > 0 ? actionsWidth : TaleedSize.modalWidth - 2 * TaleedSize.modalPadding
        let half = (width - TaleedSize.modalActionGap) / 2 - 2 * metrics.paddingX
        let category = UIContentSizeCategory(dynamicTypeSize)
        return [resolvedCancelTitle, confirmTitle].contains { metrics.textStyle.width(of: $0, sizeCategory: category) > half }
    }

    private var cancelButton: some View {
        TaleedButton(title: resolvedCancelTitle, kind: .outline,
                     size: .medium, isFullWidth: true, metrics: .modalAction, action: onCancel)
    }

    private var confirmButton: some View {
        TaleedButton(title: confirmTitle, kind: tone == .positive ? .primary : .danger, size: .medium, isFullWidth: true,
                     forcedState: forcesConfirmPressed ? .pressed : nil, metrics: .modalAction, action: onConfirm)
    }
}
