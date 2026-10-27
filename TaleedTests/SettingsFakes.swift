import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - Fixtures and fakes

extension AccountProfile {
    static func fixture(username: String? = "amina", isVerified: Bool = false, email: String = "amina@example.com",
                        emailVerified: Bool = true, firstName: String = "Amina", lastName: String = "Benali",
                        bio: String? = "Bio", phone: String? = nil, wilaya: CatalogWilaya? = CatalogWilaya(id: 16, name: "Alger"),
                        usernameNextChangeAt: Date? = nil, newsletter: Bool = true, hasPassword: Bool = true) -> AccountProfile {
        AccountProfile(id: "u1", username: username, displayName: username.map { "@\($0)" } ?? "Membre", avatarURL: nil,
                       isVerified: isVerified, isOfficial: false, email: email, emailVerified: emailVerified,
                       firstName: firstName, lastName: lastName, bio: bio, phone: phone, wilaya: wilaya,
                       usernameNextChangeAt: usernameNextChangeAt, newsletter: newsletter, hasPassword: hasPassword)
    }
}

@MainActor
final class FakeAccountApi: AccountApi {
    var profile = AccountProfile.fixture()
    var billingInfo = BillingInfo()
    var accountResults: [Result<AccountProfile, Taleed.ApiError>] = []
    var updateProfileError: Taleed.ApiError?
    var updateBillingError: Taleed.ApiError?
    var usernameError: Taleed.ApiError?
    var emailError: Taleed.ApiError?
    var resendError: Taleed.ApiError?
    var passwordErrors: [Taleed.ApiError?] = []
    var newsletterError: Taleed.ApiError?
    var deleteError: Taleed.ApiError?
    private(set) var profileChanges: [ProfileChanges] = []
    private(set) var billingUpdates: [BillingInfo] = []
    private(set) var usernames: [String] = []
    private(set) var emails: [String] = []
    private(set) var resends = 0
    private(set) var passwordCalls: [(current: String, new: String)] = []
    private(set) var deletions: [String?] = []
    var setupLinkError: Taleed.ApiError?
    private(set) var setupLinkEmails: [String] = []
    private(set) var accountCalls = 0

    func account(automatic: Bool) async throws(Taleed.ApiError) -> AccountProfile {
        accountCalls += 1
        if !accountResults.isEmpty { return try accountResults.removeFirst().get() }
        return profile
    }

    func updateProfile(_ changes: ProfileChanges) async throws(Taleed.ApiError) -> AccountProfile {
        profileChanges.append(changes)
        if let updateProfileError { throw updateProfileError }
        profile = AccountProfile(id: profile.id, username: profile.username, displayName: profile.displayName, avatarURL: profile.avatarURL,
                                 isVerified: profile.isVerified, isOfficial: false, email: profile.email,
                                 emailVerified: profile.emailVerified, firstName: changes.firstName ?? profile.firstName,
                                 lastName: changes.lastName ?? profile.lastName,
                                 bio: changes.bio.map { $0.isEmpty ? nil : $0 } ?? profile.bio,
                                 phone: changes.phone.map { $0.isEmpty ? nil : $0 } ?? profile.phone,
                                 wilaya: changes.wilayaId.map { $0 == 0 ? nil : CatalogWilaya(id: $0, name: "W\($0)") } ?? profile.wilaya,
                                 usernameNextChangeAt: nil, newsletter: profile.newsletter)
        return profile
    }

    func billing() async throws(Taleed.ApiError) -> BillingInfo { billingInfo }

    func updateBilling(_ billing: BillingInfo) async throws(Taleed.ApiError) -> BillingInfo {
        billingUpdates.append(billing)
        if let updateBillingError { throw updateBillingError }
        billingInfo = billing
        return billing
    }

    func changeUsername(_ username: String) async throws(Taleed.ApiError) -> AccountProfile {
        usernames.append(username)
        if let usernameError { throw usernameError }
        profile = .fixture(username: username, usernameNextChangeAt: Date(timeIntervalSinceNow: 30 * 86400))
        return profile
    }

    func changeEmail(_ newEmail: String) async throws(Taleed.ApiError) {
        emails.append(newEmail)
        if let emailError { throw emailError }
    }

    func resendEmailVerification() async throws(Taleed.ApiError) {
        resends += 1
        if let resendError { throw resendError }
    }

    func changePassword(current: String, new: String) async throws(Taleed.ApiError) {
        passwordCalls.append((current, new))
        if !passwordErrors.isEmpty, let error = passwordErrors.removeFirst() { throw error }
    }

    func setNewsletter(_ isOn: Bool) async throws(Taleed.ApiError) -> AccountProfile {
        if let newsletterError { throw newsletterError }
        profile = .fixture(newsletter: isOn)
        return profile
    }

    func deleteAccount(password: String?) async throws(Taleed.ApiError) {
        deletions.append(password)
        if let deleteError { throw deleteError }
    }

    func sendPasswordSetupLink(email: String) async throws(Taleed.ApiError) {
        setupLinkEmails.append(email)
        if let setupLinkError { throw setupLinkError }
    }
}

@MainActor
final class FakeAddressesApi: AddressesApi {
    var list: [SavedAddress] = []
    var createError: Taleed.ApiError?
    var deleteError: Taleed.ApiError?
    var communesByWilaya: [Int: [CommuneOption]] = [16: [CommuneOption(id: 16001, name: "Alger")],
                                                    31: [CommuneOption(id: 31001, name: "Oran")]]
    private(set) var created: [AddressInput] = []
    private(set) var updates: [(id: String, changes: AddressChanges)] = []
    private(set) var deleted: [String] = []

    func addresses(automatic: Bool) async throws(Taleed.ApiError) -> [SavedAddress] { list }

    func createAddress(_ input: AddressInput) async throws(Taleed.ApiError) -> SavedAddress {
        created.append(input)
        if let createError { throw createError }
        let address = SavedAddress(id: "a\(created.count)", recipientName: input.recipientName, phone: input.phone,
                                   wilaya: CatalogWilaya(id: input.wilayaId, name: "W"), communeId: input.communeId, commune: "C",
                                   addressLine: input.addressLine, isDefault: input.isDefault || list.isEmpty)
        list.append(address)
        return address
    }

    func updateAddress(id: String, changes: AddressChanges) async throws(Taleed.ApiError) -> SavedAddress {
        updates.append((id, changes))
        if changes.isDefault == true {
            list = list.map { address in
                SavedAddress(id: address.id, recipientName: address.recipientName, phone: address.phone, wilaya: address.wilaya,
                             communeId: address.communeId, commune: address.commune, addressLine: address.addressLine,
                             isDefault: address.id == id)
            }
        }
        return list.first { $0.id == id }
            ?? SavedAddress(id: id, recipientName: "K", phone: "0550123456", wilaya: CatalogWilaya(id: changes.wilayaId ?? 16, name: "W"),
                            communeId: changes.communeId, commune: "C", addressLine: "R", isDefault: false)
    }

    func deleteAddress(id: String) async throws(Taleed.ApiError) {
        deleted.append(id)
        if let deleteError { throw deleteError }
        list.removeAll { $0.id == id }
    }

    func communes(wilayaId: Int) async throws(Taleed.ApiError) -> [CommuneOption] { communesByWilaya[wilayaId] ?? [] }
}

@MainActor
final class FakeBlocksApi: BlocksApi {
    var pages: [String?: Page<BlockedMemberRow>] = [:]
    var unblockError: Taleed.ApiError?
    private(set) var unblocked: [String] = []

    func blocks(cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<BlockedMemberRow> {
        pages[cursor] ?? Page(items: [], nextCursor: nil, total: 0)
    }

    func unblock(username: String) async throws(Taleed.ApiError) {
        unblocked.append(username)
        if let unblockError { throw unblockError }
    }
}

func invalid(_ paths: String...) -> Taleed.ApiError {
    .failed(ApiFailure(status: 400, code: .invalidRequest, issues: paths.map { ApiFieldIssue(path: $0, message: "bad") }))
}

func failure(_ code: ApiErrorCode, status: Int = 409) -> Taleed.ApiError {
    .failed(ApiFailure(status: status, code: code))
}

@MainActor
func signedInStore(_ api: FakeAccountApi) async -> (AccountStore, SessionManager) {
    let session = SessionManager(api: FakeTaleedApi(),
                                 apiSession: ApiSession(environment: .fixture(), language: .fr, configuration: .init()),
                                 tokenStore: InMemoryTokenStore())
    session.didAuthenticate(token: "t", user: .fixture())
    let store = AccountStore(api: api, session: session)
    await store.loadIfNeeded()
    return (store, session)
}
