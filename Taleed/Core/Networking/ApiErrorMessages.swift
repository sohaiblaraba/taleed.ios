import Foundation

/// The app's text for each error (api-guide.md, Error codes). The API's `message` is English for
/// developers and is never shown.
///
/// Screens that do more than show a message switch on `error.code` first (highlight a field from
/// `issues`, open the order of `orderId`, show the offer bounds) and fall back to `messageKey`.
extension ApiError {
    /// The message for this error. `.rateLimited` with a wait over a minute has its own wording: use
    /// `message(in:)` or `LanguageManager.message(for:)`, which say how many minutes.
    var messageKey: L10nKey {
        switch self {
        case .network: return .commonErrorNetwork
        case .server: return .commonErrorGeneric
        case .unauthorized: return .authSignInRequired
        case .banned: return .suspendedTitle
        case .invalidCredentials: return .authErrorInvalidCredentials
        case .rateLimited: return .appErrorRateLimited
        case let .unknown(status, _): return status >= 500 ? .commonErrorGeneric : .authErrorGeneric
        case let .failed(failure): return Self.messageKey(for: failure.code, status: failure.status)
        }
    }

    // One case per code keeps the table readable.
    // swiftlint:disable:next cyclomatic_complexity
    static func messageKey(for code: ApiErrorCode, status: Int) -> L10nKey {
        switch code {
        case .invalidRequest: .appErrorInvalidRequest
        case .invalidUsername: .authErrorUsernameInvalid
        case .passwordTooShort: .settingsPasswordTooShort
        case .passwordTooLong: .appErrorPasswordTooLong
        case .wrongPassword: .settingsPasswordWrongError
        case .offerOutOfRange: .appErrorOfferOutOfRange
        case .promoInvalid: .checkoutPromoInvalid
        case .unauthorized: .authSignInRequired
        case .invalidCredentials: .authErrorInvalidCredentials
        case .banned: .suspendedTitle
        case .forbidden: .appErrorForbidden
        case .inviteRequired: .appErrorInviteRequired
        case .blocked: .commonBlocked
        case .conversationReadOnly: .chatBlockedReadOnly
        case .notFound: .appNotFoundTitle
        case .emailTaken: .authErrorEmailExists
        case .usernameTaken: .authErrorUsernameTaken
        case .usernameCooldown: .appErrorUsernameCooldown
        case .nameLocked: .settingsNameLockedHint
        case .accountExists: .authRequestAccessAccountExists
        case .alreadyRequested: .authRequestAccessAlreadyRequested
        case .listingLocked: .appErrorListingLocked
        case .listingUnavailable: .checkoutErrorListingUnavailable
        case .offerPending: .offersErrorActive
        case .offerClosed: .appErrorOfferClosed
        case .alreadyReported: .reportAlreadyReported
        case .invalidState, .disputeExists, .alreadyReviewed: .appErrorInvalidState
        case .priceChanged: .appErrorPriceChanged
        case .paymentMethodUnavailable: .checkoutErrorMethodUnavailable
        case .insufficientBalance: .walletErrorAmount
        case .addressLimit: .appErrorAddressLimit
        case .ordersInProgress: .settingsDeleteBlockedActiveOrders
        case .disputeInProgress: .settingsDeleteBlockedOpenDisputes
        case .payoutInProgress: .settingsDeleteBlockedPendingPayout
        case .walletNotEmpty: .settingsDeleteBlockedWallet
        case .fileTooLarge: .appErrorFileTooLarge
        case .unsupportedMediaType: .appErrorUnsupportedMedia
        case .rateLimited: .appErrorRateLimited
        case ._internal: .commonErrorGeneric
        case .carrierError: .ordersLabelCarrierError
        case .featureDisabled: .visualErrorDisabled
        case .shippingUnavailable: .appErrorShippingUnavailable
        case .paymentUnavailable: .appErrorPaymentUnavailable
        // A code added after this build: by its status.
        case .unknownDefaultOpenApi: status >= 500 ? .commonErrorGeneric : .authErrorGeneric
        }
    }

    /// Minutes to show for a wait over a minute ("try again in 3 minutes"), nil for a shorter or
    /// unknown wait ("try again in a moment"). api-guide.md, Rate limits.
    var rateLimitMinutes: Int? {
        guard let seconds = retryAfter, seconds > 60 else { return nil }
        return Int((Double(seconds) / 60).rounded(.up))
    }

    /// The message in `language`.
    func message(in language: AppLanguage) -> String {
        if let minutes = rateLimitMinutes {
            return DesignSystemStrings.format(.appErrorRateLimitedMinutes, locale: language.locale, minutes)
        }
        return DesignSystemStrings.string(messageKey, language: language)
    }
}

extension LanguageManager {
    /// The app's message for an API error, in the app language.
    func message(for error: ApiError) -> String {
        error.message(in: language)
    }

    /// A string with `%d` / `%@` arguments (plurals included), in the app language.
    func format(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: language.locale, arguments: arguments)
    }
}
