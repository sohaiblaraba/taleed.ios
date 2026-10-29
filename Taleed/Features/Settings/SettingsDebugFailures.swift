#if DEBUG
import Foundation

/// `-TaleedDebugSettings offline` fails the first request of each settings load once, offline (then they
/// work): the hub's account rows (`GET /me`), the profile form (`GET /me/billing`), the addresses and the
/// blocked members. `newsletter` fails the first newsletter change offline: the switch flips back. Both:
/// `offline,newsletter`. For screenshots of the error and offline states (screens.md §0.6).
/// `-TaleedDebugDelete unauthorized`: "Oui, supprimer mon compte" answers `401` without calling the API,
/// as the retry after a lost answer once the account is gone (slice E, Retrying). `orders`: it answers
/// `409 orders_in_progress`, `payout`: `409 payout_in_progress`, `admin`: `403 forbidden`, each time and
/// without calling the API (the refused screen, with nothing deleted).
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

    /// `-TaleedDebugDelete orders|payout|admin`: the refusal, without calling the API.
    static func deletionRefusal() -> ApiError? {
        switch UserDefaults.standard.string(forKey: "TaleedDebugDelete") {
        case "orders": .failed(ApiFailure(status: 409, code: .ordersInProgress))
        case "payout": .failed(ApiFailure(status: 409, code: .payoutInProgress))
        case "admin": .failed(ApiFailure(status: 403, code: .forbidden))
        default: nil
        }
    }

    static func fail(_ point: Point) throws(ApiError) {
        let modes = (UserDefaults.standard.string(forKey: "TaleedDebugSettings") ?? "").split(separator: ",").map(String.init)
        let isOn = point == .newsletter ? modes.contains("newsletter") : modes.contains("offline")
        guard isOn, !used.contains(point) else { return }
        used.insert(point)
        throw .network
    }
}
#endif
