import Foundation
@testable import Taleed
import Testing
import UIKit

/// Slice I copy: the consent steps and the sign-up line with the age statement, in every language.
@MainActor
struct AiConsentCopyTests {
    @Test func theSignUpLineStatesTheAgeAndKeepsBothLinks() {
        let expected: [AppLanguage: String] = [
            .en: "By continuing, you confirm you are 18 or older and agree to Taleed's Terms of Use and Privacy Policy.",
            .fr: "En continuant, vous confirmez avoir 18 ans ou plus et accepter les conditions d’utilisation et la "
                + "politique de confidentialité de Taleed.",
            .ar: "بالمتابعة، فإنك تؤكد أن عمرك 18 عامًا أو أكثر وأنك توافق على شروط الاستخدام وسياسة الخصوصية الخاصة بـ Taleed.",
        ]
        for (language, plain) in expected {
            let text = LanguageManager.localizedString(.authTermsConsent, language: language)
            #expect(text.contains("<terms>") && text.contains("</terms>") && text.contains("<privacy>") && text.contains("</privacy>"))
            #expect(LegalText.plain(text) == plain, "\(language)")
        }
    }

    @Test func theConsentStepsHaveTheirTextInEveryLanguage() {
        let keys: [L10nKey] = [
            .settingsVerificationAiConsentTitle, .settingsVerificationAiConsentBody, .settingsVerificationAiConsentAgree,
            .settingsVerificationAiConsentDecline, .settingsVerificationAiConsentDeclineHint,
            .visualConsentTitle, .visualConsentBody, .visualConsentAgree, .visualConsentCancel,
        ]
        for language in AppLanguage.allCases {
            for key in keys {
                let text = LanguageManager.localizedString(key, language: language)
                #expect(!text.isEmpty && text != key.rawValue, "\(key.rawValue) \(language)")
            }
        }
        #expect(LanguageManager.localizedString(.settingsVerificationAiConsentAgree, language: .en) == "Agree and continue")
        #expect(LanguageManager.localizedString(.settingsVerificationAiConsentDecline, language: .fr)
            == "Continuer sans vérification automatique")
        #expect(LanguageManager.localizedString(.visualConsentTitle, language: .ar) == "البحث بالصورة عبر Jina AI")
    }
}

/// A small PNG, as a picked ID photo.
private func idPhoto() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 18))
    return renderer.image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
    }.pngData() ?? Data()
}

/// Identity verification's consent to OpenAI's first check (slice I, acceptance checks 1 to 5).
@MainActor
struct IdentityAiConsentTests {
    let api = FakeIdentityVerificationApi()
    let account = FakeAccountApi()
    let uploads = FakeIdUploads()

    private func model(status: IdentityStatus = .none, profile: AccountProfile = .fixture(firstName: "Yacine", lastName: "Kaci"))
        async -> IdentityVerificationViewModel {
        api.status = status
        account.profile = profile
        let (store, _) = await signedInStore(account)
        let uploads = uploads
        let model = IdentityVerificationViewModel(api: api, account: account, store: store) { data throws(Taleed.ApiError) in
            try uploads.upload(data)
        }
        await model.load()
        return model
    }

    @Test func withoutAiReviewTheRequestGoesWithoutConsentOrStep() async {
        let model = await model()
        model.photoPicked(idPhoto())
        await model.submitTapped(identityAiReview: false)
        #expect(!model.asksAiConsent)
        #expect(api.submittedConsents == [nil])
        #expect(model.status == .pending)
    }

    @Test func withAiReviewTheStepComesFirstAndAgreeingSendsTrue() async {
        let model = await model()
        model.photoPicked(idPhoto())
        await model.submitTapped(identityAiReview: true)
        #expect(model.asksAiConsent)
        // Nothing is uploaded or sent before the answer.
        #expect(uploads.uploads.isEmpty)
        #expect(api.submittedKeys.isEmpty)
        await model.answerAiConsent(true)
        #expect(!model.asksAiConsent)
        #expect(api.submittedConsents == [true])
        #expect(model.status == .pending)
    }

    @Test func decliningSendsFalseForTheManualReview() async {
        let model = await model()
        model.photoPicked(idPhoto())
        await model.submitTapped(identityAiReview: true)
        await model.answerAiConsent(false)
        #expect(api.submittedConsents == [false])
        #expect(model.notice == .submitted)
    }

    @Test func dismissingTheStepSendsNothingAndKeepsTheForm() async {
        let model = await model()
        let data = idPhoto()
        model.photoPicked(data)
        await model.submitTapped(identityAiReview: true)
        // Swiped down: the sheet's binding sets it back to false.
        model.asksAiConsent = false
        #expect(uploads.uploads.isEmpty)
        #expect(api.submittedKeys.isEmpty)
        #expect(model.photo?.data == data)
        #expect(model.canSubmit)
        // A late answer after the sheet closed sends nothing either.
        await model.answerAiConsent(true)
        #expect(api.submittedKeys.isEmpty)
    }

    @Test func aResubmissionAfterARefusalAsksAgain() async {
        let model = await model(status: .rejected(note: "Photo floue"))
        model.photoPicked(idPhoto())
        await model.submitTapped(identityAiReview: true)
        #expect(model.asksAiConsent)
        await model.answerAiConsent(true)
        #expect(api.submittedConsents == [true])
    }

    @Test func anInvalidNameStopsBeforeTheStep() async {
        let model = await model(profile: .fixture(firstName: "Y", lastName: "Kaci"))
        model.photoPicked(idPhoto())
        await model.submitTapped(identityAiReview: true)
        #expect(!model.asksAiConsent)
        #expect(model.nameError(.firstName) == .nameLength)
    }
}
