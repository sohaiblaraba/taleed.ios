import Foundation

/// Turns a website address, a push's `data.url`, a notification's `url` or the app's URL scheme into
/// an `AppDestination` (screens.md §1.2, slice-d.md and slice-e.md "Opening links and pushes").
///
/// The path decides, whatever the host (pushes carry the server's own address, `http://localhost:3000`
/// locally). An optional `/ar`, `/en` (or `/fr`) prefix is stripped first. Anything the table does not
/// list, admin pages included, leads Home.
enum LinkRouter {
    /// The app's URL scheme in this build (`TaleedURLScheme` in Info.plist): `taleed` in production.
    static let appScheme = (Bundle.main.object(forInfoDictionaryKey: "TaleedURLScheme") as? String)?.lowercased() ?? "taleed"

    private static let languagePrefixes: Set<String> = ["ar", "en", "fr"]

    static func destination(for url: URL) -> AppDestination {
        let scheme = url.scheme?.lowercased() ?? ""
        var segments: [String]
        switch scheme {
        case "http", "https", "":
            segments = pathSegments(url.path(percentEncoded: false))
        case appScheme:
            // `taleed://payment-return?…`; `taleed://listings/42` reads like the path `/listings/42`.
            let host = url.host(percentEncoded: false) ?? ""
            if host == "payment-return" { return paymentReturn(url) ?? .home }
            segments = pathSegments(host + "/" + url.path(percentEncoded: false))
        default:
            return .home
        }
        if let first = segments.first, languagePrefixes.contains(first.lowercased()) {
            segments.removeFirst()
        }
        return destination(segments: segments, query: queryItems(url))
    }

    /// A link given as text: an absolute URL or a path such as `/listings/42`.
    static func destination(for link: String) -> AppDestination {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return .home }
        return destination(for: url)
    }

    // MARK: Paths

    // One line per path: the table of screens.md §1.2.
    // swiftlint:disable:next cyclomatic_complexity
    private static func destination(segments: [String], query: [String: String]) -> AppDestination {
        switch segments.first {
        case "listings": return listing(segments, query: query)
        case "members": return member(segments, query: query)
        case "browse": return segments.count == 1 ? .explore(exploreQuery(query)) : .home
        case "categories": return categories(segments, query: query)
        case "visual-search": return single(segments) { .screen(.visualSearch(id: $0)) }
        case "sell": return segments.count == 1 ? .sell : .home
        case "favorites": return segments.count == 1 ? .screen(.favorites) : .home
        case "inbox":
            if segments.count == 1 { return .inbox }
            return single(segments) { .screen(.conversation(id: $0)) }
        case "bundle": return single(segments) { .screen(.bundle(id: $0)) }
        case "checkout":
            return single(segments) { listingId in
                .screen(.checkout(CheckoutTarget(listingId: listingId, offerId: query["offer"], bundleId: query["bundle"])))
            }
        case "orders":
            if segments.count == 1 { return .screen(.orders) }
            return single(segments) { .screen(.order(id: $0)) }
        case "wallet": return segments.count == 1 ? .screen(.wallet) : .home
        case "notifications": return segments.count == 1 ? .screen(.notifications) : .home
        case "settings": return segments.count == 1 ? .screen(.settings) : .home
        case "referrals": return segments.count == 1 ? .screen(.referrals) : .home
        case "r": return single(segments) { .signUp(referralCode: $0) }
        default: return .home
        }
    }

    /// `/listings/{id}` and `/listings/{id}/chat?with={memberId}`.
    private static func listing(_ segments: [String], query: [String: String]) -> AppDestination {
        guard segments.count >= 2, !segments[1].isEmpty else { return .home }
        let id = segments[1]
        switch segments.count {
        case 2:
            return .screen(.listing(id: id))
        case 3 where segments[2] == "chat":
            if let member = query["with"] { return .listingChat(listingId: id, memberId: member) }
            return .screen(.listing(id: id))
        default:
            return .home
        }
    }

    /// `/members/{username}`, with the website's wardrobe filter (`?category=&sort=`); `?bundle=1` (the
    /// website's "Achète en lot" link) opens the bundle builder over the profile.
    private static func member(_ segments: [String], query: [String: String]) -> AppDestination {
        guard segments.count == 2, let name = username(segments[1]) else { return .home }
        if query["bundle"] == "1" { return .screen(.bundleBuilder(username: name)) }
        var wardrobe = WardrobeQuery()
        wardrobe.category = query["category"]
        wardrobe.sort = query["sort"].flatMap(WardrobeQuery.Sort.init(rawValue:)) ?? .newest
        return .screen(.member(username: name, wardrobe: wardrobe))
    }

    /// `/categories/{slug}` and `/categories/{parent}/{slug}`: the last slug is the category.
    private static func categories(_ segments: [String], query: [String: String]) -> AppDestination {
        guard segments.count == 2 || segments.count == 3, let slug = segments.last else { return .home }
        var filters = exploreQuery(query)
        filters.category = slug
        return .explore(filters)
    }

    /// A path of exactly two segments, the second one an identifier.
    private static func single(_ segments: [String], _ make: (String) -> AppDestination) -> AppDestination {
        guard segments.count == 2, !segments[1].isEmpty else { return .home }
        return make(segments[1])
    }

    private static func username(_ value: String) -> String? {
        let name = value.hasPrefix("@") ? String(value.dropFirst()) : value
        return name.isEmpty ? nil : name
    }

    static func exploreQuery(_ query: [String: String]) -> ExploreQuery {
        ExploreQuery(
            text: query["q"],
            category: query["category"],
            brand: query["brand"],
            wilaya: query["wilaya"].flatMap { Int($0) },
            condition: query["condition"],
            size: query["size"],
            // The website's own addresses say `min` and `max` (`FiltersBar`); the API's names work too.
            minPrice: (query["minPrice"] ?? query["min"]).flatMap { Int($0) },
            maxPrice: (query["maxPrice"] ?? query["max"]).flatMap { Int($0) },
            sort: query["sort"]
        )
    }

    // MARK: Payment return

    private static func paymentReturn(_ url: URL) -> AppDestination? {
        let query = queryItems(url)
        guard let id = query["id"] else { return nil }
        let kind: PaymentReturn.Kind
        switch query["kind"] {
        case "order": kind = .order
        case "top_up": kind = .topUp
        default: return nil
        }
        return .paymentReturn(PaymentReturn(kind: kind, id: id, succeeded: query["result"] == "success"))
    }

    // MARK: Parsing

    private static func pathSegments(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// The query's values, trimmed; empty values count as absent. The first of a repeated name wins.
    private static func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var result: [String: String] = [:]
        for item in items {
            guard let value = item.value?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
                  result[item.name] == nil else { continue }
            result[item.name] = value
        }
        return result
    }
}
