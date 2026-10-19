import Foundation
@testable import Taleed
import Testing

@MainActor
struct ConfirmationHostTests {
    private static func modal(_ title: String) -> ConfirmationModalCard {
        ConfirmationModalCard(title: title, message: "", confirmTitle: "OK", onConfirm: {}, onCancel: {})
    }

    @Test func aModalShowsOnlyWhileItsTabIsOnScreen() {
        let host = ConfirmationHost()
        let owner = UUID()
        host.present(Self.modal("Bloquer @amina ?"), owner: owner, tab: .home)
        #expect(host.presentation(in: .home)?.modal.title == "Bloquer @amina ?")
        // A link opened another tab: hidden there, back with its tab.
        #expect(host.presentation(in: .explore) == nil)
        host.dismiss(owner: owner)
        #expect(host.presentation(in: .home) == nil)
    }

    @Test func onlyItsOwnerTakesAModalAway() {
        let host = ConfirmationHost()
        let first = UUID()
        let second = UUID()
        host.present(Self.modal("first"), owner: first, tab: .home)
        host.present(Self.modal("second"), owner: second, tab: .home)
        #expect(host.presentation(in: .home)?.modal.title == "second")
        host.dismiss(owner: UUID())
        host.dismiss(owner: second)
        #expect(host.presentation(in: .home)?.modal.title == "first")
        // Updated text keeps its place.
        host.present(Self.modal("first, updated"), owner: first, tab: .home)
        #expect(host.presentation(in: .home)?.modal.title == "first, updated")
    }

    @Test func aModalOutsideTheTabsShowsOverEveryTab() {
        let host = ConfirmationHost()
        host.present(Self.modal("x"), owner: UUID(), tab: nil)
        #expect(host.presentation(in: .profile) != nil)
    }
}
