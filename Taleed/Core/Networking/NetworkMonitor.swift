import Network
import Observation
import SwiftUI

/// Whether the device has a network path, for the offline banner (Android's `ConnectivityMonitor`).
/// Online until the system says otherwise, so the banner never flashes at launch.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        #if DEBUG
        // `-TaleedDebugOffline YES`: show the banner while the simulator is online (screenshots).
        if UserDefaults.standard.bool(forKey: "TaleedDebugOffline") {
            isOnline = false
            return
        }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOnline != isOnline else { return }
                self.isOnline = isOnline
            }
        }
        // The app's one monitor lives as long as the app: never cancelled.
        monitor.start(queue: DispatchQueue(label: "app.taleed.network-monitor"))
    }
}

/// "Vous êtes hors ligne…" while the device is offline (Android's shell banner): above the tab bar, or
/// above the bottom bar of a screen that hides it (a conversation, checkout). Nothing when online.
struct OfflineBanner: View {
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        if let network, !network.isOnline {
            InlineAlert(kind: .warning, title: l10n.string(.appOfflineBanner))
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.vertical, TaleedSpacing.s8)
                .background(TaleedColor.surfacePrimary)
                .transition(.opacity)
        }
    }
}
