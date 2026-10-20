#if DEBUG
import Foundation

/// `-TaleedDebugSettings offline` fails the first request of each settings load once, offline (then they
/// work): the hub's account rows (`GET /me`), the profile form (`GET /me/billing`), the addresses and the
/// blocked members. `newsletter` fails the first newsletter change offline: the switch flips back. Both:
/// `offline,newsletter`. For screenshots of the error and offline states (screens.md §0.6).
/// `-TaleedDebugDelete unauthorized`: "Oui, supprimer mon compte" answers `401` without calling the API,
/// as the retry after a lost answer once the account is gone (slice E, Retrying).
@MainActor
enum SettingsDebugFailures {
    enum Point: String {
        case account, billing, addresses, blocks, newsletter
    }

    private static var used: Set<Point> = []

    /// `-TaleedDebugDelete unauthorized`, once.
    static func answersDeletionUnauthorized() -> Bool {
        guard UserDefaults.standard.string(forKey: "TaleedDebugDelete") == "unauthorized", !deletionAnswered else { return false }
        deletionAnswered = true
        return true
    }

    private static var deletionAnswered = false

    static func fail(_ point: Point) throws(ApiError) {
        let modes = (UserDefaults.standard.string(forKey: "TaleedDebugSettings") ?? "").split(separator: ",").map(String.init)
        let isOn = point == .newsletter ? modes.contains("newsletter") : modes.contains("offline")
        guard isOn, !used.contains(point) else { return }
        used.insert(point)
        throw .network
    }
}
#endif
