import Foundation

/// On-device checks of the auth forms, for instant feedback only: the server decides
/// (screens.md §0.1). Lengths count UTF-16 code units, as the server does.
enum AuthValidation {
    /// Text fields are trimmed before their length is checked and before they are sent, except
    /// passwords (screens.md G1).
    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One `@`, something on both sides, a dot in the domain, no spaces.
    static func isValidEmail(_ email: String) -> Bool {
        let email = trimmed(email)
        return email.utf16.count <= AuthRules.emailMaxLength && email.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil
    }

    /// `^[a-zA-Z0-9][a-zA-Z0-9._-]{2,29}$` (`src/lib/username.ts`): 3 to 30 characters, starting with a
    /// letter or a digit.
    static func isValidUsername(_ username: String) -> Bool {
        trimmed(username).wholeMatch(of: /[a-zA-Z0-9][a-zA-Z0-9._-]{2,29}/) != nil
    }

    /// First or family name: 2 to 30 characters once trimmed.
    static func isValidNamePart(_ name: String) -> Bool {
        (AuthRules.namePartMinLength...AuthRules.namePartMaxLength).contains(trimmed(name).utf16.count)
    }

    enum PasswordProblem: Equatable {
        case tooShort, tooLong
    }

    /// A new password: 8 to 128 characters, spaces included.
    static func newPasswordProblem(_ password: String) -> PasswordProblem? {
        let length = password.utf16.count
        if length < AuthRules.passwordMinLength { return .tooShort }
        if length > AuthRules.passwordMaxLength { return .tooLong }
        return nil
    }

    /// The referral code to send: what the member typed, trimmed, or nil when empty. The API ignores
    /// a malformed code (slice F, decision 12).
    static func referralCodeToSend(_ typed: String) -> String? {
        let code = trimmed(typed)
        return code.isEmpty ? nil : code
    }

    /// A code from a `/r/{code}` link, to prefill the field: lowercased, and dropped when it is not
    /// a code (the website sets no referral for such a link).
    static func referralCode(fromLink code: String) -> String? {
        let code = trimmed(code).lowercased()
        return code.wholeMatch(of: /[0-9a-f]{8}/) != nil ? code : nil
    }

    /// Keeps at most `maxLength` UTF-16 code units, for fields with a hard limit.
    static func limited(_ text: String, to maxLength: Int) -> String {
        guard text.utf16.count > maxLength else { return text }
        var result = ""
        for character in text {
            guard result.utf16.count + character.utf16.count <= maxLength else { break }
            result.append(character)
        }
        return result
    }
}

/// A field error of an auth form, resolved to text by the view.
enum AuthFieldError: Equatable, Sendable {
    case emailInvalid
    case nameLength
    case usernameInvalid
    case usernameTaken
    case emailTaken
    case passwordTooShort
    case passwordTooLong
    /// The server refused the field without a code of its own (`invalid_request`).
    case invalid
}

/// A message above or under an auth form: one of the app's strings, or the app's text for an error.
enum FormMessage: Equatable, Sendable {
    case key(L10nKey)
    case error(ApiError)
}

extension LanguageManager {
    func text(for error: AuthFieldError) -> String {
        switch error {
        case .emailInvalid: string(.appAuthEmailInvalid)
        case .nameLength: format(.appAuthNameLength, AuthRules.namePartMinLength, AuthRules.namePartMaxLength)
        case .usernameInvalid: string(.authErrorUsernameInvalid)
        case .usernameTaken: string(.authErrorUsernameTaken)
        case .emailTaken: string(.authErrorEmailExists)
        case .passwordTooShort: string(.settingsPasswordTooShort)
        case .passwordTooLong: string(.appErrorPasswordTooLong)
        case .invalid: string(.appErrorInvalidRequest)
        }
    }

    func text(for message: FormMessage) -> String {
        switch message {
        case let .key(key): string(key)
        case let .error(error): self.message(for: error)
        }
    }
}
