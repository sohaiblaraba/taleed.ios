import Foundation
import Observation

@MainActor
@Observable
final class SignInViewModel {
    var email = ""
    var password = ""
    private(set) var isLoading = false
    /// The message to show under the form, by error code.
    private(set) var errorKey: L10nKey?

    @ObservationIgnored private let session: SessionManager

    init(session: SessionManager) {
        self.session = session
    }

    var canSubmit: Bool {
        !isLoading && !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    /// Returns true when the sheet should close: signed in, or suspended (the suspended screen
    /// replaces the shell).
    func submit() async -> Bool {
        guard canSubmit else { return false }
        isLoading = true
        errorKey = nil
        defer { isLoading = false }
        do {
            try await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            return true
        } catch {
            errorKey = Self.messageKey(for: error)
            return error == .banned
        }
    }

    static func messageKey(for error: ApiError) -> L10nKey? {
        switch error {
        case .invalidCredentials: .authErrorInvalidCredentials
        case .rateLimited: .authErrorRateLimited
        case .network: .commonErrorNetwork
        case .banned: nil
        default: .commonErrorGeneric
        }
    }
}
