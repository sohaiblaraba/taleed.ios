import Foundation

/// What the profile offers, from the server's flags only (screens.md §0.1, §2 G5 "Actions", slice C
/// "Blocking"). Signed out, the member's actions show and ask to sign in first (screens.md §0.5).
struct MemberProfileActions: Equatable, Sendable {
    enum Primary: Equatable, Sendable {
        /// "Suivre" (`following` false) or "Suivi" (true).
        case follow(following: Bool)
        /// The member blocked this one: "Débloquer" replaces Follow.
        case unblock
        /// The member's own profile: "Modifier le profil" and "Mes annonces".
        case ownProfile
    }

    let primary: Primary
    /// "Achète en lot" (the bundle builder).
    let showsShopBundle: Bool
    /// The menu's Block or Unblock. Never on the member's own profile, nor on Taleed's official account
    /// (the API answers `403 forbidden` to both, slice C "Blocking").
    let showsBlockMenu: Bool
    let showsReport: Bool
    /// The "You blocked @x" notice.
    let showsBlockedNotice: Bool

    init(profile: MemberProfile) {
        if profile.isMe {
            primary = .ownProfile
        } else if profile.isBlocked {
            primary = .unblock
        } else {
            primary = .follow(following: profile.isFollowing)
        }
        showsShopBundle = !profile.isMe && !profile.isBlocked && profile.canBundle
        showsBlockMenu = !profile.isMe && (!profile.isOfficial || profile.isBlocked)
        showsReport = !profile.isMe
        showsBlockedNotice = !profile.isMe && profile.isBlocked
    }
}

/// The wardrobe filter's choices (screens.md §7 G5, the website's `WardrobeFilters`).
enum WardrobeFilterRules {
    /// The category select shows only when the member sells in more than one category.
    static func showsCategoryPicker(_ categories: [WardrobeCategory]) -> Bool {
        categories.count > 1
    }

    /// A category's label: its name, with the parent's next to a name two categories share
    /// ("Vêtements · Femmes", slice A).
    static func label(for category: WardrobeCategory, among categories: [WardrobeCategory]) -> String {
        let shared = categories.filter {
            $0.name.compare(category.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard shared.count > 1, let parent = category.parentName, !parent.isEmpty else { return category.name }
        return "\(category.name) · \(parent)"
    }

    /// The categories in the website's order: by label, in the app language's collation.
    static func sorted(_ categories: [WardrobeCategory], locale: Locale) -> [WardrobeCategory] {
        categories.sorted {
            label(for: $0, among: categories).compare(label(for: $1, among: categories), options: [.caseInsensitive],
                                                      range: nil, locale: locale) == .orderedAscending
        }
    }

    /// How many items a category choice shows ("Voir les 3 résultats"): the category's count, or the
    /// whole wardrobe for "Toutes les catégories".
    static func count(for category: String?, total: Int, categories: [WardrobeCategory]) -> Int {
        guard let category else { return total }
        return categories.first { $0.matches(category) }?.count ?? 0
    }

    /// The query a link asked for, without a category the member does not sell in (it would show an
    /// empty wardrobe the filter cannot undo). A category's id (the website's links) or slug both name
    /// it, and stay as they are: the API takes either.
    static func sanitized(_ query: WardrobeQuery, categories: [WardrobeCategory]) -> WardrobeQuery {
        var result = query
        if let category = query.category, !categories.contains(where: { $0.matches(category) }) {
            result.category = nil
        }
        return result
    }
}

/// The text of the "verified information" list, and of the stars (VoiceOver).
enum MemberProfileText {
    /// "Membre depuis 19 oct. 2026": the app's date (`OrderText.date`).
    static func memberSince(_ date: Date, locale: Locale) -> String {
        OrderText.date(date, locale: locale)
    }
}
