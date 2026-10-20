import SwiftUI
import TaleedAPI

/// The calls of the account settings (screens.md §2 G16, slice E "The settings screen").
@MainActor
protocol AccountApi: AnyObject {
    /// `GET /me` with the private fields. `automatic`: a refresh the member did not ask for.
    func account(automatic: Bool) async throws(ApiError) -> AccountProfile
    /// `PATCH /me`, only the changed fields. `409 name_locked` while the identity is verified.
    func updateProfile(_ changes: ProfileChanges) async throws(ApiError) -> AccountProfile
    /// `GET /me/billing`.
    func billing() async throws(ApiError) -> BillingInfo
    /// `PUT /me/billing`: every field; one left out is cleared.
    func updateBilling(_ billing: BillingInfo) async throws(ApiError) -> BillingInfo
    /// `POST /me/username`. `409 username_taken`, `409 username_cooldown`, `400` on `body.username`.
    func changeUsername(_ username: String) async throws(ApiError) -> AccountProfile
    /// `POST /me/email`: always `204`; the link goes to the new address.
    func changeEmail(_ newEmail: String) async throws(ApiError)
    /// `POST /me/email/verification`. `409 invalid_state`: already verified.
    func resendEmailVerification() async throws(ApiError)
    /// `POST /me/password`. `400 wrong_password` on `body.currentPassword`.
    func changePassword(current: String, new: String) async throws(ApiError)
    /// `PATCH /me/preferences {newsletter}`.
    func setNewsletter(_ isOn: Bool) async throws(ApiError) -> AccountProfile
    /// `POST /me/delete`. `204`: every session has ended, this one too.
    func deleteAccount(password: String) async throws(ApiError)
}

extension AccountApi {
    func account() async throws(ApiError) -> AccountProfile { try await account(automatic: false) }
}

/// The saved delivery addresses (slice D, Saved addresses). An app feature: the website has none.
@MainActor
protocol AddressesApi: AnyObject {
    /// `GET /me/addresses`: the default first, then the most recent; 10 at most.
    func addresses(automatic: Bool) async throws(ApiError) -> [SavedAddress]
    /// `POST /me/addresses`. Not idempotent: the member's tap only. `409 address_limit` past 10.
    func createAddress(_ input: AddressInput) async throws(ApiError) -> SavedAddress
    /// `PATCH /me/addresses/{id}`.
    func updateAddress(id: String, changes: AddressChanges) async throws(ApiError) -> SavedAddress
    /// `DELETE /me/addresses/{id}`. A repeat after it went through is `404`: the caller treats it as done.
    func deleteAddress(id: String) async throws(ApiError)
    /// `GET /wilayas/{id}/communes`.
    func communes(wilayaId: Int) async throws(ApiError) -> [CommuneOption]
}

/// The members the member blocked (slice C, Blocking).
@MainActor
protocol BlocksApi: AnyObject {
    /// `GET /me/blocks`: most recent first, 50 a page.
    func blocks(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<BlockedMemberRow>
    /// `DELETE /members/{username}/block`: idempotent.
    func unblock(username: String) async throws(ApiError)
}

extension GeneratedTaleedApi: AccountApi {
    func account(automatic: Bool) async throws(ApiError) -> AccountProfile {
        #if DEBUG
        try SettingsDebugFailures.fail(.account)
        #endif
        return AccountProfile(try await caller.call(.read, automatic: automatic) { try await AccountAPI.getMe(apiConfiguration: $0) })
    }

    func updateProfile(_ changes: ProfileChanges) async throws(ApiError) -> AccountProfile {
        let body = ProfileUpdate(firstName: changes.firstName, lastName: changes.lastName, bio: changes.bio, phone: changes.phone,
                                 wilayaId: changes.wilayaId, avatarKey: changes.avatarKey)
        // It sets values: safe to repeat (slice E, Retrying).
        return AccountProfile(try await caller.call(.read) { try await AccountAPI.updateMe(profileUpdate: body, apiConfiguration: $0) })
    }

    func billing() async throws(ApiError) -> BillingInfo {
        #if DEBUG
        try SettingsDebugFailures.fail(.billing)
        #endif
        return BillingInfo(try await caller.call(.read) { try await AccountAPI.getBilling(apiConfiguration: $0) })
    }

    func updateBilling(_ billing: BillingInfo) async throws(ApiError) -> BillingInfo {
        let body = BillingDetailsInput(name: billing.name, address: billing.address, commune: billing.commune,
                                       wilayaId: billing.wilayaId, zip: billing.zip)
        return BillingInfo(try await caller.call(.read) {
            try await AccountAPI.updateBilling(billingDetailsInput: body, apiConfiguration: $0)
        })
    }

    func changeUsername(_ username: String) async throws(ApiError) -> AccountProfile {
        let body = UsernameChange(username: username)
        // A repeat that went through answers 200 and changes nothing (slice E, Retrying).
        return AccountProfile(try await caller.call(.read) {
            try await AccountAPI.changeUsername(usernameChange: body, apiConfiguration: $0)
        })
    }

    func changeEmail(_ newEmail: String) async throws(ApiError) {
        let body = EmailChange(newEmail: newEmail)
        // Each call sends an email: from a button only.
        try await caller.call(.write) { try await AccountAPI.changeEmail(emailChange: body, apiConfiguration: $0) }
    }

    func resendEmailVerification() async throws(ApiError) {
        try await caller.call(.write) { try await AccountAPI.resendEmailVerification(apiConfiguration: $0) }
    }

    func changePassword(current: String, new: String) async throws(ApiError) {
        let body = PasswordChange(currentPassword: current, newPassword: new)
        // Never the same body twice: once it went through, the old password is wrong.
        try await caller.call(.write) { try await AccountAPI.changePassword(passwordChange: body, apiConfiguration: $0) }
    }

    func setNewsletter(_ isOn: Bool) async throws(ApiError) -> AccountProfile {
        let body = PreferencesUpdate(newsletter: isOn)
        return AccountProfile(try await caller.call(.read) {
            try await AccountAPI.updatePreferences(preferencesUpdate: body, apiConfiguration: $0)
        })
    }

    func deleteAccount(password: String) async throws(ApiError) {
        #if DEBUG
        if SettingsDebugFailures.answersDeletionUnauthorized() {
            // As a retry after a lost answer: the server ended the session, so the token is rejected.
            caller.record(.unauthorized, sentToken: caller.session.token)
            throw .unauthorized
        }
        #endif
        let body = AccountDeletion(password: password)
        // Password attempts are counted (5 per 15 minutes): the member's tap only.
        try await caller.call(.write) { try await AccountAPI.deleteAccount(accountDeletion: body, apiConfiguration: $0) }
    }
}

extension GeneratedTaleedApi: AddressesApi {
    func addresses(automatic: Bool) async throws(ApiError) -> [SavedAddress] {
        #if DEBUG
        try SettingsDebugFailures.fail(.addresses)
        #endif
        let list = try await caller.call(.read, automatic: automatic) { try await AddressesAPI.listAddresses(apiConfiguration: $0) }
        return list.items.map(SavedAddress.init)
    }

    func createAddress(_ input: AddressInput) async throws(ApiError) -> SavedAddress {
        let body = AddressCreate(recipientName: input.recipientName, phone: input.phone, wilayaId: input.wilayaId,
                                 communeId: input.communeId, addressLine: input.addressLine, isDefault: input.isDefault)
        // Each call saves another address.
        return SavedAddress(try await caller.call(.write) {
            try await AddressesAPI.createAddress(addressCreate: body, apiConfiguration: $0)
        })
    }

    func updateAddress(id: String, changes: AddressChanges) async throws(ApiError) -> SavedAddress {
        let body = AddressUpdate(recipientName: changes.recipientName, phone: changes.phone, wilayaId: changes.wilayaId,
                                 communeId: changes.communeId, addressLine: changes.addressLine, isDefault: changes.isDefault)
        return SavedAddress(try await caller.call(.read) {
            try await AddressesAPI.updateAddress(id: id, addressUpdate: body, apiConfiguration: $0)
        })
    }

    func deleteAddress(id: String) async throws(ApiError) {
        try await caller.call(.read) { try await AddressesAPI.deleteAddress(id: id, apiConfiguration: $0) }
    }
}

extension GeneratedTaleedApi: BlocksApi {
    func blocks(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<BlockedMemberRow> {
        #if DEBUG
        try SettingsDebugFailures.fail(.blocks)
        #endif
        let page = try await caller.call(.read, automatic: automatic) {
            try await SafetyAPI.listBlocks(cursor: cursor, apiConfiguration: $0)
        }
        return Page(items: page.items.map(BlockedMemberRow.init), nextCursor: page.nextCursor, total: page.total)
    }

    func unblock(username: String) async throws(ApiError) {
        try await caller.call(.read) { try await SafetyAPI.unblockMember(username: username, apiConfiguration: $0) }
    }
}

// MARK: - Mapping

extension AccountProfile {
    init(_ me: Me) {
        self.init(
            id: me.id,
            username: me.username,
            displayName: me.displayName,
            avatarURL: me.avatarUrl.flatMap(URL.init(string:)),
            isVerified: me.isVerified,
            isOfficial: me.isOfficial,
            email: me.email,
            emailVerified: me.emailVerified,
            firstName: me.firstName,
            lastName: me.lastName,
            bio: me.bio,
            phone: me.phone,
            wilaya: me.wilaya.map { CatalogWilaya(id: $0.id, name: $0.name) },
            usernameNextChangeAt: me.usernameNextChangeAt,
            newsletter: me.preferences.newsletter,
            unreadMessages: me.counts.unreadMessages,
            unreadNotifications: me.counts.unreadNotifications
        )
    }
}

private extension BillingInfo {
    init(_ billing: BillingDetails) {
        self.init(name: billing.name, address: billing.address, commune: billing.commune, wilayaId: billing.wilaya?.id,
                  zip: billing.zip)
    }
}

private extension BlockedMemberRow {
    init(_ block: BlockedMember) {
        let member = block.member
        self.init(id: member.id, username: member.username, displayName: member.displayName,
                  avatarURL: member.avatarUrl.flatMap(URL.init(string:)), isVerified: member.isVerified,
                  isOfficial: member.isOfficial, blockedAt: block.blockedAt)
    }
}

// MARK: - Dependencies

/// What the settings screens need. Set once at the root (`AppRootView`).
struct SettingsDependencies {
    let account: any AccountApi
    let addresses: any AddressesApi
    let blocks: any BlocksApi
    /// Identity verification (G17).
    let verification: any IdentityVerificationApi
    let uploads: PhotoUploadService
}

private struct SettingsDependenciesKey: EnvironmentKey {
    static var defaultValue: SettingsDependencies? { nil }
}

extension EnvironmentValues {
    var settingsDependencies: SettingsDependencies? {
        get { self[SettingsDependenciesKey.self] }
        set { self[SettingsDependenciesKey.self] = newValue }
    }
}
