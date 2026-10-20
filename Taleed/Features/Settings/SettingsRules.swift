import Foundation
import TaleedAPI

/// The limits of the settings fields, from the contract (`ProfileUpdate`, `BillingDetailsInput`,
/// `AddressCreate`) and the website (`src/lib/account-rules.ts`). On-device checks only give instant
/// feedback: the API decides.
enum AccountLimits {
    static let namePartMin = ProfileUpdate.firstNameRule.minLength ?? 2
    static let namePartMax = ProfileUpdate.firstNameRule.maxLength ?? 30
    static let bioMax = ProfileUpdate.bioRule.maxLength ?? 500
    static let phoneMax = ProfileUpdate.phoneRule.maxLength ?? 30
    static let billingNameMax = BillingDetailsInput.nameRule.maxLength ?? 80
    static let billingAddressMax = BillingDetailsInput.addressRule.maxLength ?? 200
    static let billingCommuneMax = BillingDetailsInput.communeRule.maxLength ?? 80
    static let billingZipMax = BillingDetailsInput.zipRule.maxLength ?? 10
    static let usernameMax = 30
    static let emailMax = AuthRules.emailMaxLength
    static let passwordMin = AuthRules.passwordMinLength
    static let passwordMax = AuthRules.passwordMaxLength
    static let recipientNameMin = AddressCreate.recipientNameRule.minLength ?? 2
    static let recipientNameMax = AddressCreate.recipientNameRule.maxLength ?? 80
    static let addressLineMax = AddressCreate.addressLineRule.maxLength ?? 200
    /// A member keeps 10 addresses at most (`409 address_limit`).
    static let addressesMax = 10
}

enum AccountRules {
    /// The profile phone as the server keeps it: Arabic-Indic digits become Latin ones; spaces, dots
    /// and dashes are dropped (`normalizePhone`, `src/lib/checkout-rules.ts`).
    static func normalizedPhone(_ typed: String) -> String {
        CheckoutRules.latinDigits(typed).filter { !$0.isWhitespace && $0 != "." && $0 != "-" }
    }

    /// Empty (removes the number), or `0` then 8 or 9 digits.
    static func isValidOptionalPhone(_ typed: String) -> Bool {
        let phone = normalizedPhone(typed)
        return phone.isEmpty || phone.wholeMatch(of: /0[0-9]{8,9}/) != nil
    }

    /// The handle as the API keeps it: trimmed, lowercase (`normalizeUsername`).
    static func normalizedUsername(_ typed: String) -> String {
        AuthValidation.trimmed(typed).lowercased()
    }

    /// The address to send: trimmed and lowercase, as the website sends it.
    static func normalizedEmail(_ typed: String) -> String {
        AuthValidation.trimmed(typed).lowercased()
    }

    /// The same name written with other spaces is the same name (`sameName`).
    static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        let normalize = { (value: String) in value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return normalize(lhs) == normalize(rhs)
    }

    /// Text to send for an optional field: trimmed, nil when empty.
    static func optional(_ text: String) -> String? {
        let value = AuthValidation.trimmed(text)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Profile and billing

/// The fields of the profile card that can show an error, in screen order.
enum ProfileField: Hashable, Sendable, CaseIterable {
    case avatar, firstName, lastName, bio, phone, wilaya
    case billingName, billingAddress, billingCommune, billingZip, billingWilaya
}

/// An error under a profile field, resolved to text by the view.
enum ProfileFieldError: Equatable, Sendable {
    /// 2 to 30 characters.
    case nameLength
    /// The identity is verified (`409 name_locked`).
    case nameLocked
    /// Not `0` then 8 or 9 digits.
    case phoneInvalid
    /// The format passed but the server refused it (a number left by a suspended account).
    case phoneRefused
    /// The API refused the field (`invalid_request` with an issue on it).
    case invalid
}

/// The photo of the profile form: as it is, a new upload, or removed.
enum AvatarChange: Equatable, Sendable {
    case unchanged
    case uploaded(key: String, url: URL?)
    case removed
}

/// The profile and billing card of the website (`settings-form.tsx`), saved together with one Save:
/// `PATCH /me` with the changed fields, then `PUT /me/billing` with every field.
struct ProfileForm: Equatable, Sendable {
    var firstName = ""
    var lastName = ""
    var bio = ""
    var phone = ""
    var wilayaId: Int?
    var avatar = AvatarChange.unchanged
    var billingName = ""
    var billingAddress = ""
    var billingCommune = ""
    var billingWilayaId: Int?
    var billingZip = ""

    init() {}

    init(profile: AccountProfile, billing: BillingInfo) {
        firstName = profile.firstName
        lastName = profile.lastName
        bio = profile.bio ?? ""
        phone = profile.phone ?? ""
        wilayaId = profile.wilaya?.id
        billingName = billing.name ?? ""
        billingAddress = billing.address ?? ""
        billingCommune = billing.commune ?? ""
        billingWilayaId = billing.wilayaId
        billingZip = billing.zip ?? ""
    }

    /// The first word is the first name, the rest the family name, as the website joins them.
    var legalName: String {
        "\(AuthValidation.trimmed(firstName)) \(AuthValidation.trimmed(lastName))".trimmingCharacters(in: .whitespaces)
    }

    /// The device's checks: the names (unless locked) and the phone.
    func errors(nameLocked: Bool) -> [ProfileField: ProfileFieldError] {
        var errors: [ProfileField: ProfileFieldError] = [:]
        if !nameLocked {
            if !AuthValidation.isValidNamePart(firstName) { errors[.firstName] = .nameLength }
            if !AuthValidation.isValidNamePart(lastName) { errors[.lastName] = .nameLength }
        }
        if !AccountRules.isValidOptionalPhone(phone) { errors[.phone] = .phoneInvalid }
        return errors
    }

    /// `PATCH /me`: the fields that differ from `saved`. The name is left out while it is locked; a name
    /// that only differs by its spaces is not a change. Empty values remove (`""`, wilaya `0`).
    func profileChanges(from saved: ProfileForm, nameLocked: Bool) -> ProfileChanges {
        var changes = ProfileChanges()
        if !nameLocked {
            if !AccountRules.sameName(firstName, saved.firstName) { changes.firstName = AuthValidation.trimmed(firstName) }
            if !AccountRules.sameName(lastName, saved.lastName) { changes.lastName = AuthValidation.trimmed(lastName) }
        }
        let bio = AuthValidation.trimmed(self.bio)
        if bio != AuthValidation.trimmed(saved.bio) { changes.bio = bio }
        let phone = AccountRules.normalizedPhone(self.phone)
        if phone != AccountRules.normalizedPhone(saved.phone) { changes.phone = phone }
        if wilayaId != saved.wilayaId { changes.wilayaId = wilayaId ?? 0 }
        switch avatar {
        case .unchanged: break
        case let .uploaded(key, _): changes.avatarKey = key
        case .removed: changes.avatarKey = ""
        }
        return changes
    }

    /// `PUT /me/billing`: every field, empty ones left out (cleared).
    var billing: BillingInfo {
        BillingInfo(name: AccountRules.optional(billingName), address: AccountRules.optional(billingAddress),
                    commune: AccountRules.optional(billingCommune), wilayaId: billingWilayaId,
                    zip: AccountRules.optional(billingZip))
    }

    func billingChanged(from saved: ProfileForm) -> Bool {
        billing != saved.billing
    }

    /// Something to save.
    func hasChanges(from saved: ProfileForm, nameLocked: Bool) -> Bool {
        !profileChanges(from: saved, nameLocked: nameLocked).isEmpty || billingChanged(from: saved)
    }

    /// The field of an API issue (`body.phone` of `PATCH /me`, `body.zip` of `PUT /me/billing`).
    static func field(ofProfileIssue path: String) -> ProfileField? {
        switch path {
        case "body.firstName": .firstName
        case "body.lastName": .lastName
        case "body.bio": .bio
        case "body.phone": .phone
        case "body.wilayaId": .wilaya
        case "body.avatarKey": .avatar
        default: nil
        }
    }

    static func field(ofBillingIssue path: String) -> ProfileField? {
        switch path {
        case "body.name": .billingName
        case "body.address": .billingAddress
        case "body.commune": .billingCommune
        case "body.zip": .billingZip
        case "body.wilayaId": .billingWilaya
        default: nil
        }
    }
}

// MARK: - Username

/// What "Changer de nom d'utilisateur" says before sending (`username-form.tsx`).
enum UsernameCheck: Equatable, Sendable {
    /// Nothing typed: the button stays disabled.
    case empty
    /// `usernameRuleHint` as the error.
    case invalid
    /// `usernameSameError`: the API would answer 200 and change nothing.
    case same
    case ready(String)

    init(typed: String, current: String?) {
        let candidate = AccountRules.normalizedUsername(typed)
        if candidate.isEmpty {
            self = .empty
        } else if !AuthValidation.isValidUsername(candidate) {
            self = .invalid
        } else if candidate == current?.lowercased() {
            self = .same
        } else {
            self = .ready(candidate)
        }
    }
}

// MARK: - Email

/// What "Envoyer le lien de confirmation" says before sending (`email-form.tsx`).
enum EmailCheck: Equatable, Sendable {
    case empty
    case invalid
    /// `emailSameError`.
    case same
    case ready(String)

    init(typed: String, current: String) {
        let email = AccountRules.normalizedEmail(typed)
        if email.isEmpty {
            self = .empty
        } else if !AuthValidation.isValidEmail(email) {
            self = .invalid
        } else if email == current.lowercased() {
            self = .same
        } else {
            self = .ready(email)
        }
    }
}

// MARK: - Password

/// A field of the password card.
enum PasswordField: Hashable, Sendable {
    case current, new, confirm
}

/// An error under a password field.
enum PasswordFieldError: Equatable, Sendable {
    /// `passwordTooShort`.
    case tooShort
    case tooLong
    /// `passwordMismatch`.
    case mismatch
    /// `passwordWrongError` (`400 wrong_password`).
    case wrong
}

struct PasswordForm: Equatable, Sendable {
    var current = ""
    var new = ""
    var confirm = ""

    /// Every field filled: the button is enabled.
    var isComplete: Bool { !current.isEmpty && !new.isEmpty && !confirm.isEmpty }

    /// The website's checks before sending: the length, then the confirmation.
    var errors: [PasswordField: PasswordFieldError] {
        switch AuthValidation.newPasswordProblem(new) {
        case .tooShort?: return [.new: .tooShort]
        case .tooLong?: return [.new: .tooLong]
        case nil: return new == confirm ? [:] : [.confirm: .mismatch]
        }
    }
}
