import Foundation

// MARK: - Addresses

/// A field of the address form.
enum AddressField: Hashable, Sendable {
    case recipientName, phone, wilaya, commune, addressLine
}

enum AddressFieldError: Equatable, Sendable {
    case nameLength
    case phoneInvalid
    case required
    /// The saved address has no commune id (saved before communes came from the carrier): pick it again.
    case communeAgain
    case invalid
}

/// The address form: `POST /me/addresses` for a new one, `PATCH` with the changes otherwise.
struct AddressForm: Equatable, Sendable {
    var recipientName = ""
    var phone = ""
    var wilayaId: Int?
    var communeId: Int?
    var addressLine = ""
    var isDefault = false

    init(recipientName: String = "", phone: String = "", wilayaId: Int? = nil, communeId: Int? = nil,
         addressLine: String = "", isDefault: Bool = false) {
        self.recipientName = recipientName
        self.phone = phone
        self.wilayaId = wilayaId
        self.communeId = communeId
        self.addressLine = addressLine
        self.isDefault = isDefault
    }

    init(_ address: SavedAddress) {
        self.init(recipientName: address.recipientName, phone: address.phone, wilayaId: address.wilaya.id,
                  communeId: address.communeId, addressLine: address.addressLine, isDefault: address.isDefault)
    }

    func errors() -> [AddressField: AddressFieldError] {
        var errors: [AddressField: AddressFieldError] = [:]
        let nameLength = AuthValidation.trimmed(recipientName).utf16.count
        if !(AccountLimits.recipientNameMin...AccountLimits.recipientNameMax).contains(nameLength) {
            errors[.recipientName] = .nameLength
        }
        if !CheckoutRules.isValidPhone(CheckoutRules.latinDigits(phone)) { errors[.phone] = .phoneInvalid }
        if wilayaId == nil { errors[.wilaya] = .required }
        // Only once a wilaya is chosen: the commune field waits for it.
        if communeId == nil, wilayaId != nil { errors[.commune] = .required }
        if AuthValidation.trimmed(addressLine).isEmpty { errors[.addressLine] = .required }
        return errors
    }

    /// The body of `POST /me/addresses`, once the form is valid.
    var input: AddressInput? {
        guard errors().isEmpty, let wilayaId, let communeId else { return nil }
        return AddressInput(recipientName: AuthValidation.trimmed(recipientName),
                            phone: AuthValidation.trimmed(CheckoutRules.latinDigits(phone)), wilayaId: wilayaId,
                            communeId: communeId, addressLine: AuthValidation.trimmed(addressLine), isDefault: isDefault)
    }

    /// `PATCH /me/addresses/{id}`: the changed fields. A new wilaya or commune sends both, as the API
    /// needs the commune with the wilaya. An address is never made "not default" here: another one
    /// takes its place.
    func changes(from saved: AddressForm) -> AddressChanges {
        var changes = AddressChanges()
        guard let input else { return changes }
        if input.recipientName != AuthValidation.trimmed(saved.recipientName) { changes.recipientName = input.recipientName }
        if input.phone != AuthValidation.trimmed(saved.phone) { changes.phone = input.phone }
        if input.wilayaId != saved.wilayaId || input.communeId != saved.communeId {
            changes.wilayaId = input.wilayaId
            changes.communeId = input.communeId
        }
        if input.addressLine != AuthValidation.trimmed(saved.addressLine) { changes.addressLine = input.addressLine }
        if isDefault, !saved.isDefault { changes.isDefault = true }
        return changes
    }

    static func field(ofIssue path: String) -> AddressField? {
        switch path {
        case "body.recipientName": .recipientName
        case "body.phone": .phone
        case "body.wilayaId": .wilaya
        case "body.communeId": .commune
        case "body.addressLine": .addressLine
        default: nil
        }
    }
}

// MARK: - Account deletion

/// Why `POST /me/delete` did not delete the account, with the screen that solves it
/// (slice E, Deleting the account; `delete-account-form.tsx`). Shown inside the form, not as a toast.
enum DeletionBlocker: Equatable, Sendable {
    case wrongPassword
    /// `orders_in_progress`: open the orders.
    case activeOrders
    /// `dispute_in_progress`: open the orders.
    case openDispute
    /// `payout_in_progress`: a payout to the member is on its way (also the answer when a small amount
    /// owed was just put in a payout, slice H): open Earnings.
    case pendingPayout
    /// `wallet_not_empty` with money owed to the member: it leaves with the next weekly payout; open
    /// Earnings (where the payout details are added).
    case walletNotEmpty
    /// `wallet_not_empty` with a refund to the member still being sent: open the orders.
    case refundToSend
    /// `wallet_not_empty` with a negative amount after an adjustment: the support contacts.
    case owesTaleed
    /// `403 forbidden`: an admin account; show the support contacts.
    case admin
    /// `429`: 5 password attempts per 15 minutes.
    case tooManyAttempts
    /// No answer: the member may try again.
    case network
    /// Anything else.
    case generic

    init(_ error: ApiError) {
        switch error.code {
        case .wrongPassword?: self = .wrongPassword
        case .ordersInProgress?: self = .activeOrders
        case .disputeInProgress?: self = .openDispute
        case .payoutInProgress?: self = .pendingPayout
        case .walletNotEmpty?: self = .walletNotEmpty
        case .forbidden?: self = .admin
        case .rateLimited?: self = .tooManyAttempts
        default: self = error == .network ? .network : .generic
        }
    }

    /// `wallet_not_empty` covers three situations (slice H): its `message` is for developers, so the app
    /// tells them apart from what is owed (`GET /wallet`), in the server's order: owed above 0, below 0,
    /// otherwise a refund still to send. `owed` nil (the wallet did not load): the owed text, the most
    /// common case.
    static func walletNotEmpty(owed: Int?) -> DeletionBlocker {
        guard let owed else { return .walletNotEmpty }
        if owed > 0 { return .walletNotEmpty }
        if owed < 0 { return .owesTaleed }
        return .refundToSend
    }

    /// The refusal's text, inside the form.
    var messageKey: L10nKey {
        switch self {
        case .wrongPassword: .settingsDeleteWrongPassword
        case .activeOrders: .settingsDeleteBlockedActiveOrders
        case .openDispute: .settingsDeleteBlockedOpenDisputes
        case .pendingPayout: .settingsDeleteBlockedPendingPayout
        case .walletNotEmpty: .settingsDeleteBlockedWallet
        case .refundToSend: .settingsDeleteBlockedRefund
        case .owesTaleed: .settingsDeleteBlockedOwesTaleed
        case .admin: .settingsDeleteBlockedAdmin
        case .tooManyAttempts: .settingsDeleteTooManyAttempts
        case .network: .commonErrorNetwork
        case .generic: .settingsDeleteBlockedGeneric
        }
    }

    /// Where the member goes to solve it.
    enum Remedy: Equatable, Sendable {
        case orders, earnings, support
    }

    var remedy: Remedy? {
        switch self {
        case .activeOrders, .openDispute, .refundToSend: .orders
        case .pendingPayout, .walletNotEmpty: .earnings
        case .admin, .owesTaleed: .support
        case .wrongPassword, .tooManyAttempts, .network, .generic: nil
        }
    }
}
