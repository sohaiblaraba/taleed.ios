import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - View models

@MainActor
struct AccountStoreTests {
    @Test func loadingUpdatesTheSessionUser() async {
        let api = FakeAccountApi()
        api.profile = .fixture(username: "amina.b", wilaya: CatalogWilaya(id: 31, name: "Oran"))
        let (store, session) = await signedInStore(api)
        #expect(store.profile?.username == "amina.b")
        #expect(session.user?.handle == "@amina.b")
        #expect(session.user?.wilayaId == 31)
    }

    @Test func aFirstFailureShowsTheErrorAndRetryLoads() async {
        let api = FakeAccountApi()
        api.accountResults = [.failure(.network)]
        let (store, _) = await signedInStore(api)
        #expect(store.loadError == .network)
        await store.retry()
        #expect(store.profile != nil)
        #expect(store.loadError == nil)
    }

    /// The website's newsletter card: a failure (offline included) puts the switch back.
    @Test func aFailedNewsletterChangeFlipsBack() async {
        let api = FakeAccountApi()
        api.profile = .fixture(newsletter: true)
        let (store, _) = await signedInStore(api)
        api.newsletterError = .network
        #expect(await !store.setNewsletter(false))
        #expect(store.newsletterPending == nil)
        #expect(store.profile?.newsletter == true)
        api.newsletterError = nil
        #expect(await store.setNewsletter(false))
        #expect(store.newsletterPending == nil)
        #expect(store.profile?.newsletter == false)
    }
}

@MainActor
struct ProfileSettingsViewModelTests {
    private func model(_ api: FakeAccountApi) async -> ProfileSettingsViewModel {
        let (store, _) = await signedInStore(api)
        let model = ProfileSettingsViewModel(api: api, store: store) { _ throws(Taleed.ApiError) in
            UploadedPhoto(key: "avatars/k", url: URL(string: "https://x/a.webp"), thumbURL: nil)
        }
        await model.loadIfNeeded()
        return model
    }

    @Test func oneSaveSendsTheChangedProfileThenEveryBillingField() async {
        let api = FakeAccountApi()
        let model = await model(api)
        model.form.phone = "0550 12 34 56"
        model.form.wilayaId = 31
        model.form.billingAddress = "12 rue Didouche Mourad"
        model.form.billingWilayaId = 16
        await model.save()
        #expect(api.profileChanges == [ProfileChanges(phone: "0550123456", wilayaId: 31)])
        #expect(api.billingUpdates == [BillingInfo(address: "12 rue Didouche Mourad", wilayaId: 16)])
        #expect(model.notice == .saved)
        #expect(model.form.phone == "0550123456")
        #expect(!model.canSave)
    }

    @Test func onlyBillingChangedSkipsPatchMe() async {
        let api = FakeAccountApi()
        api.billingInfo = BillingInfo(commune: "Alger Centre")
        let model = await model(api)
        model.form.billingCommune = ""
        await model.save()
        #expect(api.profileChanges.isEmpty)
        #expect(api.billingUpdates == [BillingInfo()])
    }

    @Test func anInvalidPhoneIsRefusedBeforeSending() async {
        let api = FakeAccountApi()
        let model = await model(api)
        model.form.phone = "12345"
        await model.save()
        #expect(api.profileChanges.isEmpty)
        #expect(model.error(.phone) == .phoneInvalid)
        #expect(model.firstErrorField == .phone)
    }

    @Test func aPhoneTheServerRefusesShowsItsOwnError() async {
        let api = FakeAccountApi()
        api.updateProfileError = invalid("body.phone")
        let model = await model(api)
        model.form.phone = "0550123456"
        await model.save()
        #expect(model.error(.phone) == .phoneRefused)
        #expect(model.notice == nil)
        model.edited(.phone)
        #expect(model.error(.phone) == nil)
    }

    @Test func aLockedNameAnswersOnTheNameFields() async {
        let api = FakeAccountApi()
        api.updateProfileError = failure(.nameLocked)
        let model = await model(api)
        model.form.firstName = "Nour"
        await model.save()
        #expect(model.error(.firstName) == .nameLocked)
        #expect(model.form.firstName == "Amina")
    }

    @Test func aBillingFailureKeepsTheSavedProfileAndShowsTheField() async {
        let api = FakeAccountApi()
        api.updateBillingError = invalid("body.zip")
        let model = await model(api)
        model.form.bio = "Nouvelle bio"
        model.form.billingZip = "1600000000"
        await model.save()
        #expect(api.profileChanges.count == 1)
        #expect(model.error(.billingZip) == .invalid)
        #expect(model.notice == nil)
        #expect(model.canSave)
    }

    @Test func aPickedPhotoIsSentWithTheFormAndRemovingSendsEmpty() async {
        let api = FakeAccountApi()
        let model = await model(api)
        await model.photoPicked(Data([1]))
        #expect(model.avatarURL?.absoluteString == "https://x/a.webp")
        #expect(model.form.profileChanges(from: model.saved!, nameLocked: false).avatarKey == "avatars/k")
        model.removePhoto()
        // No saved photo: nothing to remove.
        #expect(model.form.avatar == .unchanged)
    }
}

@MainActor
struct AccountFormViewModelTests {
    @Test func usernameSameNameIsRefusedWithoutARequest() async {
        let api = FakeAccountApi()
        let (store, _) = await signedInStore(api)
        let model = UsernameSettingsViewModel(api: api, store: store)
        model.typed = "AMINA"
        await model.submit()
        #expect(model.fieldError == .same)
        #expect(api.usernames.isEmpty)
    }

    @Test func usernameTakenThenChangedThenLocked() async {
        let api = FakeAccountApi()
        let (store, session) = await signedInStore(api)
        let model = UsernameSettingsViewModel(api: api, store: store)
        api.usernameError = failure(.usernameTaken)
        model.typed = "karim"
        await model.submit()
        #expect(model.fieldError == .taken)
        api.usernameError = nil
        model.typed = "Amina.Test"
        await model.submit()
        #expect(api.usernames.last == "amina.test")
        #expect(model.notice == .changed("amina.test"))
        #expect(model.lockedUntil != nil)
        #expect(session.user?.username == "amina.test")
        #expect(model.typed.isEmpty)
    }

    @Test func usernameCooldownReloadsTheDate() async {
        let api = FakeAccountApi()
        let (store, _) = await signedInStore(api)
        let model = UsernameSettingsViewModel(api: api, store: store)
        api.usernameError = failure(.usernameCooldown)
        let next = Date(timeIntervalSinceNow: 86400)
        api.profile = .fixture(usernameNextChangeAt: next)
        model.typed = "other.name"
        await model.submit()
        #expect(model.fieldError == .cooldown(next))
        #expect(model.lockedUntil == next)
    }

    @Test func emailSameAddressIsRefusedWithoutARequest() async {
        let api = FakeAccountApi()
        let (store, _) = await signedInStore(api)
        let model = EmailSettingsViewModel(api: api, store: store)
        model.typed = "AMINA@example.com"
        await model.submit()
        #expect(model.fieldError == .same)
        #expect(api.emails.isEmpty)
    }

    @Test func emailChangeShowsWhereTheLinkWent() async {
        let api = FakeAccountApi()
        let (store, _) = await signedInStore(api)
        let model = EmailSettingsViewModel(api: api, store: store)
        model.typed = " New@Example.com "
        await model.submit()
        #expect(api.emails == ["new@example.com"])
        #expect(model.sentTo == "new@example.com")
        #expect(model.typed.isEmpty)
    }

    /// 1.6.1: an unverified current email answers `invalid_state`; verify it first.
    @Test func emailChangeWithAnUnverifiedEmailAsksToVerifyFirst() async {
        let api = FakeAccountApi()
        let (store, _) = await signedInStore(api)
        let model = EmailSettingsViewModel(api: api, store: store)
        api.emailError = failure(.invalidState)
        api.profile = .fixture(emailVerified: false)
        model.typed = "new@example.com"
        await model.submit()
        #expect(model.fieldError == .verifyFirst)
        #expect(model.sentTo == nil)
        #expect(model.notice == nil)
        #expect(store.profile?.emailVerified == false)
    }

    @Test func resendAlreadyVerifiedReloadsTheAccount() async {
        let api = FakeAccountApi()
        api.profile = .fixture(emailVerified: false)
        let (store, _) = await signedInStore(api)
        let model = EmailSettingsViewModel(api: api, store: store)
        api.resendError = failure(.invalidState)
        api.profile = .fixture(emailVerified: true)
        await model.resend()
        #expect(store.profile?.emailVerified == true)
        #expect(!model.resent)
        #expect(model.notice == nil)
    }

    @Test func wrongCurrentPasswordIsAFieldError() async {
        let api = FakeAccountApi()
        api.passwordErrors = [failure(.wrongPassword, status: 400)]
        let model = PasswordSettingsViewModel(api: api)
        model.form = PasswordForm(current: "bad", new: "newpass99", confirm: "newpass99")
        await model.submit()
        #expect(model.error(.current) == .wrong)
        model.form.current = "sample-pass-2"
        #expect(model.error(.current) == nil)
    }

    @Test func aTooShortPasswordIsNotSent() async {
        let api = FakeAccountApi()
        let model = PasswordSettingsViewModel(api: api)
        model.form = PasswordForm(current: "sample-pass-2", new: "short12", confirm: "short12")
        await model.submit()
        #expect(api.passwordCalls.isEmpty)
        #expect(model.error(.new) == .tooShort)
    }

    @Test func afterALostAnswerTheNewPasswordIsCheckedFirst() async {
        let api = FakeAccountApi()
        api.passwordErrors = [.network, nil]
        let model = PasswordSettingsViewModel(api: api)
        model.form = PasswordForm(current: "sample-pass-2", new: "newpass99", confirm: "newpass99")
        await model.submit()
        #expect(model.notice == .error(.network))
        await model.submit()
        // The change went through the first time: the new password as both answers 204.
        #expect(api.passwordCalls.map(\.current) == ["sample-pass-2", "newpass99"])
        #expect(model.notice == .changed)
        #expect(model.form == PasswordForm())
    }

    @Test func afterALostAnswerThatDidNotGoThroughTheChangeIsSentAgain() async {
        let api = FakeAccountApi()
        api.passwordErrors = [.network, failure(.wrongPassword, status: 400), nil]
        let model = PasswordSettingsViewModel(api: api)
        model.form = PasswordForm(current: "sample-pass-2", new: "newpass99", confirm: "newpass99")
        await model.submit()
        await model.submit()
        #expect(api.passwordCalls.map(\.current) == ["sample-pass-2", "newpass99", "sample-pass-2"])
        #expect(model.notice == .changed)
    }
}
