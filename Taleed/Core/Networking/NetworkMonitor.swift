import Network
import Observation
import SwiftUI

/// Whether the device has a network path, for the offline banner (Android's `ConnectivityMonitor`).
/// Online until the system says otherwise, so the banner never flashes at launch.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    /// Called when the device has a network path again after it had none: the badges (`GET /me`) are
    /// asked again, since what failed meanwhile kept the last known counts.
    @ObservationIgnored var onBackOnline: (() -> Void)?
    @ObservationIgnored private let monitor = NWPathMonitor()

    /// `startsMonitoring: false` leaves the system monitor off (tests feed `pathDidChange(isOnline:)`).
    init(startsMonitoring: Bool = true) {
        #if DEBUG
        // `-TaleedDebugOffline YES`: show the banner while the simulator is online (screenshots).
        if UserDefaults.standard.bool(forKey: "TaleedDebugOffline") {
            isOnline = false
            return
        }
        #endif
        guard startsMonitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor [weak self] in self?.pathDidChange(isOnline: isOnline) }
        }
        // The app's one monitor lives as long as the app: never cancelled.
        monitor.start(queue: DispatchQueue(label: "app.taleed.network-monitor"))
    }

    /// The system's answer about the network path. Only a change counts; offline then online again
    /// calls `onBackOnline`.
    func pathDidChange(isOnline: Bool) {
        guard self.isOnline != isOnline else { return }
        self.isOnline = isOnline
        if isOnline { onBackOnline?() }
    }
}

/// "Vous êtes hors ligne…" while the device is offline (Android's shell banner): above the tab bar, or
/// above the bottom bar of a screen that hides it (a conversation), or itself at the bottom of a screen
/// without a bottom bar (checkout, the payment screen). Nothing when online.
struct OfflineBanner: View {
    /// The banner is the screen's bottom bar: it sits on the home indicator's inset (D-15).
    var isAtScreenBottom = false
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        if let network, !network.isOnline {
            if isAtScreenBottom {
                banner
                    .padding(.top, TaleedSpacing.s8)
                    .bottomBarPadding(TaleedSpacing.s8)
                    .bottomBarBackground(TaleedColor.surfacePrimary)
                    .transition(.opacity)
            } else {
                banner
                    .padding(.vertical, TaleedSpacing.s8)
                    .background(TaleedColor.surfacePrimary)
                    .transition(.opacity)
            }
        }
    }

    private var banner: some View {
        InlineAlert(kind: .warning, title: l10n.string(.appOfflineBanner))
            .padding(.horizontal, TaleedLayout.screenMargin)
    }
}
