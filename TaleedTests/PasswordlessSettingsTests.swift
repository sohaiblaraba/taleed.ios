import Foundation
@testable import Taleed
import Testing

// Slice G, Members without a password: `hasPassword` of `GET /me` in the settings.

@MainActor
struct PasswordlessSettingsTests {
    @Test func setAPasswordSendsTheResetLinkToTheAccountsEmail() async {
        let api = FakeAccountApi()
        let model = PasswordSettingsViewModel(api: api)
        await model.sendSetupLink(email: "yasmine@gmail.com")
        #expect(api.setupLinkEmails == ["yasmine@gmail.com"])
        #expect(model.setupLinkSent)
        // Once sent, the button gives way to "a link has been sent".
        await model.sendSetupLink(email: "yasmine@gmail.com")
        #expect(api.setupLinkEmails.count == 1)
    }

    @Test func aFailedLinkShowsTheError() async {
        let api = FakeAccountApi()
        api.setupLinkError = .network
        let model = PasswordSettingsViewModel(api: api)
        await model.sendSetupLink(email: "y@gmail.com")
        #expect(!model.setupLinkSent)
        #expect(model.notice == .error(.network))
    }

    @Test func requirementFollowsHasPassword() {
        #expect(DeleteAccountViewModel.PasswordRequirement(hasPassword: true) == .required)
        #expect(DeleteAccountViewModel.PasswordRequirement(hasPassword: false) == .none)
        #expect(DeleteAccountViewModel.PasswordRequirement(hasPassword: nil) == .optional)
        #expect(AccountProfile.fixture().hasPassword)
    }

    /// No password: no field, and `POST /me/delete` with `{}`.
    @Test func deletionWithoutAPasswordSendsNone() async {
        let api = FakeAccountApi()
        var deleted = false
        let model = DeleteAccountViewModel(api: api) { deleted = true }
        model.passwordRequirement = .none
        #expect(!model.showsPasswordField)
        #expect(model.canDelete)
        await model.delete()
        #expect(deleted)
        #expect(api.deletions == [nil])
    }

    @Test func deletionWithAPasswordStillAsksForIt() async {
        let api = FakeAccountApi()
        let model = DeleteAccountViewModel(api: api) {}
        model.passwordRequirement = .required
        #expect(model.showsPasswordField)
        #expect(!model.canDelete)
        model.password = "sample-pass-2"
        await model.delete()
        #expect(api.deletions == ["sample-pass-2"])
    }

    /// Unknown (`GET /me` answers `banned` on the suspended screen): the field shows but may stay empty.
    @Test func unknownLetsTheFieldStayEmpty() async {
        let api = FakeAccountApi()
        let model = DeleteAccountViewModel(api: api) {}
        model.passwordRequirement = .optional
        #expect(model.showsPasswordField)
        #expect(model.canDelete)
        await model.delete()
        #expect(api.deletions == [nil])
    }
}
