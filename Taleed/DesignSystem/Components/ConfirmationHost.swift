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
            TaleedColor.textPrimary.opacity(0.5)
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
