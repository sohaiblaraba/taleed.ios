import Foundation
@testable import Taleed
import Testing

/// Error codes to the app's localized messages (api-guide.md, Error codes).
struct ApiErrorMessageTests {
    @Test(arguments: [
        (ApiError.network, L10nKey.commonErrorNetwork),
        (.server(status: 502), .commonErrorGeneric),
        (.unauthorized, .appErrorUnauthorized),
        (.banned, .suspendedTitle),
        (.invalidCredentials, .authErrorInvalidCredentials),
        (.rateLimited(retryAfter: nil), .appErrorRateLimited),
        (.unknown(status: 409, code: "brand_new"), .authErrorGeneric),
        (.unknown(status: 403, code: nil), .authErrorGeneric),
        (.unknown(status: 520, code: nil), .commonErrorGeneric),
        (.failed(ApiFailure(status: 404, code: .notFound)), .appErrorNotFound),
        (.failed(ApiFailure(status: 403, code: .conversationReadOnly)), .appErrorConversationReadOnly),
        (.failed(ApiFailure(status: 409, code: .disputeExists)), .appErrorDisputeExists),
        (.failed(ApiFailure(status: 409, code: .alreadyReviewed)), .appErrorAlreadyReviewed),
        (.failed(ApiFailure(status: 503, code: .featureDisabled)), .appErrorFeatureDisabled),
        (.failed(ApiFailure(status: 403, code: .forbidden)), .appErrorForbidden),
        (.failed(ApiFailure(status: 403, code: .blocked)), .commonBlocked),
        (.failed(ApiFailure(status: 409, code: .emailTaken)), .authErrorEmailExists),
        (.failed(ApiFailure(status: 409, code: .offerPending)), .offersErrorActive),
        (.failed(ApiFailure(status: 409, code: .listingUnavailable)), .checkoutErrorListingUnavailable),
        (.failed(ApiFailure(status: 409, code: .invalidState)), .appErrorInvalidState),
        (.failed(ApiFailure(status: 409, code: .walletNotEmpty)), .settingsDeleteBlockedWallet),
        (.failed(ApiFailure(status: 413, code: .fileTooLarge)), .appErrorFileTooLarge),
        (.failed(ApiFailure(status: 415, code: .unsupportedMediaType)), .appErrorUnsupportedMediaType),
        (.failed(ApiFailure(status: 502, code: .carrierError)), .ordersLabelCarrierError),
        (.failed(ApiFailure(status: 503, code: .paymentUnavailable)), .appErrorPaymentUnavailable),
    ])
    func messageKeys(error: ApiError, key: L10nKey) {
        #expect(error.messageKey == key)
    }

    /// A code added to the contract gets a message, or the compiler stops at the switch.
    @Test func everyCodeHasAMessageInEveryLanguage() {
        for code in ApiErrorCode.allCases {
            let key = ApiError.messageKey(for: code, status: 400)
            for language in AppLanguage.allCases {
                let text = DesignSystemStrings.string(key, language: language)
                #expect(text != key.rawValue && !text.isEmpty, "\(code) in \(language)")
            }
        }
    }

    @Test func rateLimitSaysMinutesOverAMinute() {
        #expect(ApiError.rateLimited(retryAfter: 60).message(in: .en) == "Too many requests. Please try again in a moment.")
        #expect(ApiError.rateLimited(retryAfter: 162).rateLimitMinutes == 3)
        #expect(ApiError.rateLimited(retryAfter: 162).message(in: .en) == "Too many requests. Please try again in 3 minutes.")
        #expect(ApiError.rateLimited(retryAfter: 162).message(in: .fr) == "Trop de requêtes. Réessayez dans 3 minutes.")
        #expect(ApiError.rateLimited(retryAfter: 120).message(in: .ar) == "طلبات كثيرة جدًا. حاول مجددًا بعد دقيقتين.")
    }

    /// A daily limit (identity verification, 5 a day) can ask for up to 86 400 s: hours, not 1 440 minutes.
    @Test func rateLimitSaysHoursOverAnHour() {
        #expect(ApiError.rateLimited(retryAfter: 3601).rateLimitHours == 2)
        #expect(ApiError.rateLimited(retryAfter: 86_400).message(in: .en) == "Too many requests. Please try again in 24 hours.")
        #expect(ApiError.rateLimited(retryAfter: 86_400).message(in: .fr) == "Trop de requêtes. Réessayez dans 24 heures.")
        #expect(ApiError.rateLimited(retryAfter: 7200).message(in: .ar) == "طلبات كثيرة جدًا. حاول مجددًا بعد ساعتين.")
        #expect(ApiError.rateLimited(retryAfter: 5400).message(in: .en) == "Too many requests. Please try again in 2 hours.")
    }

    @Test func messagesFollowTheLanguage() {
        let error = ApiError.network
        #expect(error.message(in: .fr) == "Pas de connexion. Vérifiez votre réseau et réessayez.")
        #expect(error.message(in: .en) == "No connection. Check your network and try again.")
    }
}

/// Every app string exists in French, Arabic and English.
struct StringCatalogTests {
    @Test func everyKeyIsTranslated() {
        for key in L10nKey.allCases {
            for language in AppLanguage.allCases {
                let text = DesignSystemStrings.string(key, language: language)
                #expect(text != key.rawValue && !text.isEmpty, "\(key.rawValue) in \(language)")
            }
        }
    }
}
