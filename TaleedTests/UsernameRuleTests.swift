import Foundation
@testable import Taleed
import Testing

/// Sign-up names the part of the username rule that failed (helper and error agree, P1 polish).
@MainActor
struct UsernameRuleTests {
    @Test(arguments: [
        ("yasmine.k", nil), ("ab", .length), (String(repeating: "a", count: 31), .length), ("  ab  ", .length),
        (".yasmine", .start), ("_yasmine", .start), ("yas mine", .characters), ("yasmïne", .characters),
    ] as [(String, AuthValidation.UsernameProblem?)])
    func problem(username: String, expected: AuthValidation.UsernameProblem?) {
        #expect(AuthValidation.usernameProblem(username) == expected)
    }

    @Test func eachProblemHasItsOwnMessage() throws {
        let defaults = try #require(UserDefaults(suiteName: "UsernameRuleTests"))
        defaults.removePersistentDomain(forName: "UsernameRuleTests")
        let l10n = LanguageManager(defaults: defaults, preferredLanguages: ["fr"])
        #expect(l10n.text(for: .usernameLength) == "Entre 3 et 30 caractères.")
        #expect(l10n.text(for: .usernameStart) == "Commencez par une lettre ou un chiffre.")
        #expect(l10n.text(for: .usernameCharacters) == "Utilisez uniquement des lettres, chiffres, points, tirets et tirets bas.")
    }
}
