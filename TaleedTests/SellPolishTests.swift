import Foundation
@testable import Taleed
import Testing

/// Polish P3: Save stays off until the edit form differs from the listing (G8).
@MainActor
struct ListingEditsTests {
    private func model() -> SellViewModel {
        SellViewModel(editing: editableListing(), brands: [], memberWilayaId: 25, api: FakeEditListingApi(),
                      upload: { _ async throws(Taleed.ApiError) in throw .network })
    }

    @Test func saveStaysOffUntilSomethingDiffersFromTheListing() async {
        let model = model()
        #expect(!model.hasEdits)
        model.form.title += " "
        #expect(!model.hasEdits, "trailing spaces are not sent")
        model.form.priceText = "2300"
        #expect(model.hasEdits)
        model.form.priceText = String(editableListing().price)
        #expect(!model.hasEdits)
        model.makeCover(model.photos[1].id)
        #expect(model.hasEdits)
    }

    @Test func aNewListingCanAlwaysBePublished() {
        let model = SellViewModel(api: FakeSellApi(), upload: { _ async throws(Taleed.ApiError) in throw .network })
        #expect(model.hasEdits)
    }
}

/// Polish P3: the sell form's length errors group their numbers as prices do (G7).
struct SellLengthMessagesTests {
    @Test func theLengthLimitsAreGroupedAsPricesAre() {
        #expect(SellMessages.text(for: .descriptionLength(min: 10, max: 2000), language: .ar).contains("2.000"))
        #expect(SellMessages.text(for: .descriptionLength(min: 10, max: 2000), language: .fr).contains("2\u{202F}000"))
        #expect(!SellMessages.text(for: .descriptionLength(min: 10, max: 2000), language: .ar).contains("2,000"))
    }
}
