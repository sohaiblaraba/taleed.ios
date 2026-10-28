import Foundation
@testable import Taleed
import TaleedAPI
import Testing

@MainActor
struct AddressesViewModelTests {
    private let home = SavedAddress(id: "a1", recipientName: "Karim", phone: "0550123456", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                                    communeId: 16001, commune: "Alger", addressLine: "Rue 1", isDefault: true)
    private let work = SavedAddress(id: "a2", recipientName: "Karim", phone: "0550123456", wilaya: CatalogWilaya(id: 31, name: "Oran"),
                                    communeId: 31001, commune: "Oran", addressLine: "Rue 2", isDefault: false)

    @Test func makeDefaultReloadsTheOrder() async {
        let api = FakeAddressesApi()
        api.list = [home, work]
        let model = AddressesViewModel(api: api)
        await model.loadIfNeeded()
        await model.makeDefault(id: "a2")
        #expect(api.updates.first?.changes == AddressChanges(isDefault: true))
        #expect(model.addresses?.first { $0.isDefault }?.id == "a2")
    }

    @Test func deleteTreatsNotFoundAsDone() async {
        let api = FakeAddressesApi()
        api.list = [home, work]
        api.deleteError = failure(.notFound, status: 404)
        let model = AddressesViewModel(api: api)
        await model.loadIfNeeded()
        await model.delete(id: "a2")
        #expect(model.notice == .deleted)
    }

    @Test func tenAddressesStopAdding() async {
        let api = FakeAddressesApi()
        api.list = (0..<10).map { index in
            SavedAddress(id: "a\(index)", recipientName: "K", phone: "0550123456", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                         communeId: 16001, commune: "Alger", addressLine: "R", isDefault: index == 0)
        }
        let model = AddressesViewModel(api: api)
        await model.loadIfNeeded()
        #expect(!model.canAdd)
    }

    @Test func aNewWilayaClearsTheCommuneAndLoadsItsList() async {
        let api = FakeAddressesApi()
        let model = AddressFormViewModel(api: api, editing: home, isFirst: false, recipientName: nil, phone: nil)
        await model.selectWilaya(31)
        #expect(model.form.communeId == nil)
        #expect(model.communes.map(\.id) == [31001])
        model.selectCommune(31001)
        let saved = await model.save()
        #expect(saved != nil)
        #expect(api.updates.last?.changes == AddressChanges(wilayaId: 31, communeId: 31001))
    }

    @Test func aNewAddressIsPrefilledAndTheLimitIsShown() async {
        let api = FakeAddressesApi()
        api.createError = failure(.addressLimit)
        let model = AddressFormViewModel(api: api, editing: nil, isFirst: false, recipientName: "Amina Benali", phone: "0550123456")
        #expect(model.form.recipientName == "Amina Benali")
        await model.selectWilaya(16)
        model.selectCommune(16001)
        model.form.addressLine = "Rue 3"
        let saved = await model.save()
        #expect(saved == nil)
        #expect(model.notice == failure(.addressLimit))
        #expect(api.created.count == 1)
    }

    @Test func anOldAddressAsksForItsCommuneAgain() {
        let old = SavedAddress(id: "a9", recipientName: "Karim", phone: "0550123456", wilaya: CatalogWilaya(id: 16, name: "Alger"),
                               communeId: nil, commune: "Hydra", addressLine: "Rue", isDefault: false)
        let model = AddressFormViewModel(api: FakeAddressesApi(), editing: old, isFirst: false, recipientName: nil, phone: nil)
        #expect(model.error(.commune) == .communeAgain)
    }

    @Test func theFirstAddressIsAlwaysTheDefault() {
        let model = AddressFormViewModel(api: FakeAddressesApi(), editing: nil, isFirst: true, recipientName: nil, phone: nil)
        #expect(model.form.isDefault)
        #expect(!model.showsDefaultSwitch)
    }
}

@MainActor
struct BlockedMembersViewModelTests {
    @Test func unblockRemovesTheRow() async {
        let api = FakeBlocksApi()
        let row = BlockedMemberRow(id: "m1", username: "karim.h", displayName: "@karim.h", avatarURL: nil, isVerified: false,
                                   isOfficial: false, blockedAt: .now)
        api.pages[nil] = Page(items: [row], nextCursor: nil, total: 1)
        let model = BlockedMembersViewModel(api: api)
        await model.list.loadIfNeeded()
        await model.unblock(row)
        #expect(api.unblocked == ["karim.h"])
        #expect(model.list.items.isEmpty)
        #expect(model.notice == .unblocked("@karim.h"))
    }

    @Test func aFailedUnblockKeepsTheRow() async {
        let api = FakeBlocksApi()
        api.unblockError = .network
        let row = BlockedMemberRow(id: "m1", username: "karim.h", displayName: "@karim.h", avatarURL: nil, isVerified: false,
                                   isOfficial: false, blockedAt: .now)
        api.pages[nil] = Page(items: [row], nextCursor: nil, total: 1)
        let model = BlockedMembersViewModel(api: api)
        await model.list.loadIfNeeded()
        await model.unblock(row)
        #expect(model.list.items.count == 1)
        #expect(model.notice == .error(.network))
    }
}

@MainActor
struct DeleteAccountViewModelTests {
    @Test func successSignsOut() async {
        let api = FakeAccountApi()
        var deleted = false
        let model = DeleteAccountViewModel(api: api) { deleted = true }
        #expect(!model.canDelete)
        model.password = "sample-pass-2"
        await model.delete()
        #expect(deleted)
        #expect(api.deletions == ["sample-pass-2"])
    }

    @Test func aBlockerStaysInTheFormAndAWrongPasswordClearsOnTyping() async {
        let api = FakeAccountApi()
        api.deleteError = failure(.ordersInProgress)
        var deleted = false
        let model = DeleteAccountViewModel(api: api) { deleted = true }
        model.password = "sample-pass-2"
        await model.delete()
        #expect(model.blocker == .activeOrders)
        #expect(!deleted)
        api.deleteError = failure(.wrongPassword, status: 400)
        await model.delete()
        #expect(model.blocker == .wrongPassword)
        model.password = "sample-pass-22"
        #expect(model.blocker == nil)
    }

    @Test func walletNotEmptyReadsTheOwedAmount() async {
        let api = FakeAccountApi()
        api.deleteError = failure(.walletNotEmpty)
        let wallet = FakeWalletApi()
        let model = DeleteAccountViewModel(api: api, walletApi: wallet) {}
        model.password = "sample-pass-2"

        wallet.defaultSummary = walletSummary(owed: 80, account: nil)
        await model.delete()
        #expect(model.blocker == .walletNotEmpty)

        wallet.defaultSummary = walletSummary(owed: -250)
        await model.delete()
        #expect(model.blocker == .owesTaleed)

        wallet.defaultSummary = walletSummary(owed: 0, inPayout: 0)
        await model.delete()
        #expect(model.blocker == .refundToSend)

        wallet.summaries = [.failure(.network)]
        await model.delete()
        #expect(model.blocker == .walletNotEmpty)
    }

    @Test func aLostAnswerThenUnauthorizedMeansDeleted() async {
        let api = FakeAccountApi()
        api.deleteError = .unauthorized
        var deleted = false
        let model = DeleteAccountViewModel(api: api) { deleted = true }
        model.password = "sample-pass-2"
        await model.delete()
        #expect(deleted)
    }
}

@MainActor
struct SessionAccountTests {
    @Test func accountDeletedClearsTheSessionWithoutCallingTheApi() {
        let api = FakeTaleedApi()
        let tokens = InMemoryTokenStore(token: "t")
        let session = SessionManager(api: api, apiSession: ApiSession(environment: .fixture(), language: .fr, configuration: .init()),
                                     tokenStore: tokens)
        session.didAuthenticate(token: "t", user: .fixture())
        var called = false
        session.onAccountDeleted = { called = true }
        session.accountDeleted()
        #expect(!session.isSignedIn)
        #expect(tokens.load() == nil)
        #expect(called)
        #expect(api.signedOutTokens.isEmpty)
    }

    @Test func updateUserIgnoresAnotherMember() {
        let session = SessionManager(api: FakeTaleedApi(),
                                     apiSession: ApiSession(environment: .fixture(), language: .fr, configuration: .init()),
                                     tokenStore: InMemoryTokenStore())
        session.didAuthenticate(token: "t", user: .fixture())
        var other = User.fixture(username: "karim")
        other = User(id: "u2", username: other.username, displayName: other.displayName, avatarURL: nil, isVerified: false,
                     isOfficial: false)
        session.updateUser(other)
        #expect(session.user?.id == "u1")
        session.updateUser(.fixture(username: "amina.b"))
        #expect(session.user?.username == "amina.b")
    }
}
