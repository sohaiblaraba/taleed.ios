import Foundation
import Observation

/// Request an invite (`POST /access-requests`), while Taleed is invite-only (`betaMode`) or after a
/// sign-up answered `invite_required`. First and family name are joined into `name`, as on the website.
@MainActor
@Observable
final class RequestAccessViewModel {
    enum Field: Hashable, CaseIterable, Sendable {
        case firstName, lastName, email, phone, referralCode, message

        var issuePath: String {
            switch self {
            case .firstName, .lastName: "body.name"
            case .email: "body.email"
            case .phone: "body.phone"
            case .referralCode: "body.referralCode"
            case .message: "body.message"
            }
        }
    }

    /// What the screen shows once the request is in.
    enum Done: Equatable, Sendable {
        /// `204`: "Request received! We will email you…".
        case received
        /// `409 already_requested`: a request with this email is pending or approved.
        case alreadyRequested
    }

    var firstName = "" { didSet { clearError(.firstName, if: firstName != oldValue) } }
    var lastName = "" { didSet { clearError(.lastName, if: lastName != oldValue) } }
    var email = "" { didSet { clearError(.email, if: email != oldValue) } }
    var phone = "" { didSet { clearError(.phone, if: phone != oldValue) } }
    var referralCode = "" { didSet { clearError(.referralCode, if: referralCode != oldValue) } }
    var message = "" { didSet { clearError(.message, if: message != oldValue) } }

    private(set) var fieldErrors: [Field: AuthFieldError] = [:]
    private(set) var formMessage: FormMessage?
    /// `409 account_exists`: offer sign-in.
    private(set) var offersSignIn = false
    private(set) var done: Done?
    private(set) var isLoading = false

    @ObservationIgnored private let api: AuthApi

    init(api: AuthApi, referralCode: String? = nil) {
        self.api = api
        self.referralCode = referralCode ?? ""
    }

    var canSubmit: Bool { !isLoading }

    func localErrors() -> [Field: AuthFieldError] {
        var errors: [Field: AuthFieldError] = [:]
        if !AuthValidation.isValidNamePart(firstName) { errors[.firstName] = .nameLength }
        if !AuthValidation.isValidNamePart(lastName) { errors[.lastName] = .nameLength }
        if !AuthValidation.isValidEmail(email) { errors[.email] = .emailInvalid }
        return errors
    }

    var firstFieldInError: Field? {
        Field.allCases.first { fieldErrors[$0] != nil }
    }

    var form: AccessRequestForm {
        let phone = AuthValidation.trimmed(phone)
        let message = AuthValidation.trimmed(message)
        return AccessRequestForm(
            name: "\(AuthValidation.trimmed(firstName)) \(AuthValidation.trimmed(lastName))",
            email: AuthValidation.trimmed(email),
            phone: phone.isEmpty ? nil : phone,
            message: message.isEmpty ? nil : message,
            referralCode: AuthValidation.referralCodeToSend(referralCode)
        )
    }

    func submit() async {
        guard canSubmit else { return }
        formMessage = nil
        offersSignIn = false
        fieldErrors = localErrors()
        guard fieldErrors.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            try await api.requestAccess(form)
            done = .received
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: ApiError) {
        switch error.code {
        case .alreadyRequested:
            done = .alreadyRequested
        case .accountExists:
            formMessage = .key(.authRequestAccessAccountExists)
            offersSignIn = true
        case .invalidRequest where !error.issues.isEmpty:
            for field in Field.allCases where error.issue(at: field.issuePath) != nil {
                fieldErrors[field] = localErrors()[field] ?? .invalid
            }
            if fieldErrors.isEmpty { formMessage = .error(error) }
        default:
            formMessage = .error(error)
        }
    }

    private func clearError(_ field: Field, if changed: Bool) {
        guard changed else { return }
        fieldErrors[field] = nil
        if field == .email { offersSignIn = false }
    }
}
