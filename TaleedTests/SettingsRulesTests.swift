import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - Rules

struct AccountRulesTests {
    @Test(arguments: [
        ("0550 12 34 56", true), ("0550.12.34.56", true), ("0550-123-456", true), ("055012345", true), ("", true),
        ("٠٥٥٠١٢٣٤٥٦", true), ("12345", false), ("1550123456", false), ("05501234567", false), ("0550abc456", false),
    ])
    func optionalPhone(typed: String, valid: Bool) {
        #expect(AccountRules.isValidOptionalPhone(typed) == valid)
    }

    @Test func phoneIsNormalizedAsTheServerKeepsIt() {
        #expect(AccountRules.normalizedPhone("0550 12 34 56") == "0550123456")
        #expect(AccountRules.normalizedPhone("٠٥٥٠-١٢") == "055012")
    }

    @Test func namesWithOtherSpacesAreTheSame() {
        #expect(AccountRules.sameName("El  Houda ", "El Houda"))
        #expect(!AccountRules.sameName("El Houda", "Elhouda"))
    }

    @Test func usernameChecksBeforeSending() {
        #expect(UsernameCheck(typed: "  ", current: "amina") == .empty)
        #expect(UsernameCheck(typed: "ab", current: "amina") == .invalid)
        #expect(UsernameCheck(typed: ".amina", current: "amina") == .invalid)
        #expect(UsernameCheck(typed: " Amina ", current: "amina") == .same)
        #expect(UsernameCheck(typed: "Amina.B", current: "amina") == .ready("amina.b"))
        #expect(UsernameCheck(typed: "new_name", current: nil) == .ready("new_name"))
    }

    @Test func emailChecksBeforeSending() {
        #expect(EmailCheck(typed: "", current: "a@b.dz") == .empty)
        #expect(EmailCheck(typed: "nope", current: "a@b.dz") == .invalid)
        #expect(EmailCheck(typed: " A@B.dz ", current: "a@b.dz") == .same)
        #expect(EmailCheck(typed: "New@Example.com", current: "a@b.dz") == .ready("new@example.com"))
    }

    @Test func passwordChecksLengthThenConfirmation() {
        #expect(PasswordForm(current: "x", new: "short12", confirm: "other").errors == [.new: .tooShort])
        #expect(PasswordForm(current: "x", new: String(repeating: "a", count: 129), confirm: "").errors == [.new: .tooLong])
        #expect(PasswordForm(current: "x", new: "longenough", confirm: "longenougj").errors == [.confirm: .mismatch])
        #expect(PasswordForm(current: "x", new: "longenough", confirm: "longenough").errors.isEmpty)
        #expect(!PasswordForm(current: "", new: "longenough", confirm: "longenough").isComplete)
    }
}

struct ProfileFormTests {
    private let saved = ProfileForm(profile: .fixture(phone: "0550123456"),
                                    billing: BillingInfo(name: nil, address: "12 rue", commune: "Alger Centre", wilayaId: 16, zip: nil))

    @Test func noChangeSendsNothing() {
        #expect(saved.profileChanges(from: saved, nameLocked: false).isEmpty)
        #expect(!saved.hasChanges(from: saved, nameLocked: false))
    }

    @Test func onlyChangedFieldsAreSentAndEmptyValuesRemove() {
        var form = saved
        form.bio = " "
        form.phone = ""
        form.wilayaId = nil
        form.avatar = .removed
        let changes = form.profileChanges(from: saved, nameLocked: false)
        #expect(changes == ProfileChanges(bio: "", phone: "", wilayaId: 0, avatarKey: ""))
    }

    @Test func phoneWithSpacesIsNotAChangeWhenTheDigitsAreTheSame() {
        var form = saved
        form.phone = "0550 12 34 56"
        #expect(form.profileChanges(from: saved, nameLocked: false).phone == nil)
    }

    @Test func aLockedNameIsNeverSent() {
        var form = saved
        form.firstName = "Nour"
        #expect(form.profileChanges(from: saved, nameLocked: true).firstName == nil)
        #expect(form.profileChanges(from: saved, nameLocked: false).firstName == "Nour")
        #expect(form.errors(nameLocked: true).isEmpty)
    }

    @Test func nameAndPhoneAreCheckedOnTheDevice() {
        var form = saved
        form.firstName = "A"
        form.phone = "12345"
        #expect(form.errors(nameLocked: false) == [.firstName: .nameLength, .phone: .phoneInvalid])
    }

    @Test func billingSendsEveryFieldAndEmptyOnesAreLeftOut() {
        var form = saved
        form.billingCommune = "  "
        form.billingZip = "16000"
        #expect(form.billing == BillingInfo(name: nil, address: "12 rue", commune: nil, wilayaId: 16, zip: "16000"))
        #expect(form.billingChanged(from: saved))
    }

    @Test func issuesMapToTheirFields() {
        #expect(ProfileForm.field(ofProfileIssue: "body.phone") == .phone)
        #expect(ProfileForm.field(ofProfileIssue: "body.avatarKey") == .avatar)
        #expect(ProfileForm.field(ofBillingIssue: "body.zip") == .billingZip)
        #expect(ProfileForm.field(ofBillingIssue: "body.wilayaId") == .billingWilaya)
        #expect(ProfileForm.field(ofProfileIssue: "body.other") == nil)
    }
}

struct AddressFormTests {
    private let address = SavedAddress(id: "a1", recipientName: "Karim Hadj", phone: "0550123456",
                                       wilaya: CatalogWilaya(id: 31, name: "Oran"), communeId: 31001, commune: "Oran",
                                       addressLine: "Cité 200", isDefault: true)

    @Test func everyFieldIsCheckedOnTheDevice() {
        let form = AddressForm(recipientName: "K", phone: "123")
        #expect(form.errors() == [.recipientName: .nameLength, .phone: .phoneInvalid, .wilaya: .required, .addressLine: .required])
        var picked = form
        picked.wilayaId = 16
        #expect(picked.errors()[.commune] == .required)
    }

    @Test func aValidFormGivesTheBody() {
        let form = AddressForm(recipientName: " Karim ", phone: "0550 12 34 56", wilayaId: 16, communeId: 16001,
                               addressLine: " Rue 1 ", isDefault: true)
        #expect(form.input == AddressInput(recipientName: "Karim", phone: "0550 12 34 56", wilayaId: 16, communeId: 16001,
                                           addressLine: "Rue 1", isDefault: true))
    }

    @Test func anEditSendsTheChangesAndTheWilayaWithItsCommune() {
        let saved = AddressForm(address)
        var form = saved
        form.addressLine = "Cité 300"
        #expect(form.changes(from: saved) == AddressChanges(addressLine: "Cité 300"))
        form.wilayaId = 16
        form.communeId = 16001
        #expect(form.changes(from: saved) == AddressChanges(wilayaId: 16, communeId: 16001, addressLine: "Cité 300"))
    }

    @Test func aDefaultAddressIsNeverUnsetByAnEdit() {
        let saved = AddressForm(address)
        var form = saved
        form.isDefault = false
        #expect(form.changes(from: saved).isDefault == nil)
    }
}

struct DeletionBlockerTests {
    @Test func eachRefusalHasItsMessageAndRemedy() {
        #expect(DeletionBlocker(failure(.wrongPassword, status: 400)) == .wrongPassword)
        #expect(DeletionBlocker(failure(.ordersInProgress)).remedy == .orders)
        #expect(DeletionBlocker(failure(.disputeInProgress)).remedy == .orders)
        #expect(DeletionBlocker(failure(.payoutInProgress)) == .pendingPayout)
        #expect(DeletionBlocker(failure(.payoutInProgress)).remedy == .earnings)
        #expect(DeletionBlocker(failure(.walletNotEmpty)) == .walletNotEmpty)
        #expect(DeletionBlocker(failure(.walletNotEmpty)).remedy == .earnings)
        #expect(DeletionBlocker(failure(.forbidden, status: 403)).remedy == .support)
        #expect(DeletionBlocker(.rateLimited(retryAfter: 600)) == .tooManyAttempts)
        #expect(DeletionBlocker(.network) == .network)
        #expect(DeletionBlocker(.server(status: 500)) == .generic)
        #expect(DeletionBlocker(.unknown(status: 409, code: "new_code")) == .generic)
    }

    /// `wallet_not_empty` covers three situations (slice H), told apart from what is owed.
    @Test func walletNotEmptyFollowsTheOwedAmount() {
        #expect(DeletionBlocker.walletNotEmpty(owed: 4200) == .walletNotEmpty)
        #expect(DeletionBlocker.walletNotEmpty(owed: 50) == .walletNotEmpty)
        #expect(DeletionBlocker.walletNotEmpty(owed: -300) == .owesTaleed)
        #expect(DeletionBlocker.walletNotEmpty(owed: 0) == .refundToSend)
        // The amounts did not load: the owed text, never a blank refusal.
        #expect(DeletionBlocker.walletNotEmpty(owed: nil) == .walletNotEmpty)
        #expect(DeletionBlocker.refundToSend.remedy == .orders)
        #expect(DeletionBlocker.owesTaleed.remedy == .support)
    }
}

struct SupportPhoneTests {
    @Test func anAlgerianNumberReadsInGroups() {
        #expect(SupportPhone.grouped("+213540693236") == "+213 540 69 32 36")
        #expect(SupportPhone.grouped("0540693236") == "0540 69 32 36")
    }

    @Test func anythingElseStaysAsSent() {
        #expect(SupportPhone.grouped("+33 1 23 45 67 89") == "+33 1 23 45 67 89")
        #expect(SupportPhone.grouped("+213 540 69 32 36") == "+213 540 69 32 36")
    }
}

struct AppDateTests {
    /// One date format in every place: the cooldown, "member since" and the orders write the same date.
    @Test func everyScreenUsesTheSameDate() {
        let date = Date(timeIntervalSince1970: 1_795_132_800) // 2026-11-20
        #expect(OrderText.date(date, locale: AppLanguage.fr.formattingLocale) == "20\u{00A0}nov.\u{00A0}2026")
        #expect(OrderText.date(date, locale: AppLanguage.en.formattingLocale) == "20\u{00A0}Nov\u{00A0}2026")
        #expect(OrderText.date(date, locale: AppLanguage.ar.formattingLocale) == "20\u{200F}/11\u{200F}/2026")
        for language in AppLanguage.allCases {
            #expect(MemberProfileText.memberSince(date, locale: language.formattingLocale)
                == OrderText.date(date, locale: language.formattingLocale))
        }
    }
}
