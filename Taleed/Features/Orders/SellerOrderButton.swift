import SwiftUI

/// A seller's button on the order screen (screens.md §2 G13, §7 G12/G13 "Buttons and confirmations";
/// website `order-actions.tsx`): "Bordereau d'expédition", "Imprimer le bordereau", "Générer le vrai
/// bordereau", "Accepter la réclamation", "Contester". The first button of the screen is the main one
/// (mint, decision D-10); a running action shows its spinner and keeps the others still.
struct SellerOrderButton: View {
    let action: OrderRules.MemberAction
    let isFirst: Bool
    let busy: OrderDetailViewModel.Busy?
    let perform: (OrderRules.MemberAction) -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        if let spec {
            TaleedButton(title: l10n.string(spec.title), kind: isFirst ? .secondary : .outline, size: .large,
                         leadingIcon: spec.icon, isLoading: busy == spec.busy, isFullWidth: true) {
                perform(action)
            }
            .disabled(busy != nil)
            .accessibilityIdentifier("order.\(spec.identifier)")
        }
    }

    private struct Spec {
        let title: L10nKey
        let icon: TaleedIcon
        let busy: OrderDetailViewModel.Busy
        let identifier: String
    }

    private var spec: Spec? {
        switch action {
        case .ship: Spec(title: .ordersGetShippingLabel, icon: .truck, busy: .shipping, identifier: "ship")
        case .printLabel: Spec(title: .ordersDownloadLabel, icon: .share, busy: .printing, identifier: "printLabel")
        case .replaceTestLabel:
            Spec(title: .ordersGetRealShippingLabel, icon: .truck, busy: .shipping, identifier: "replaceTestLabel")
        case .acceptClaim:
            Spec(title: .disputesAcceptClaim, icon: .checkCircle, busy: .answering(.accept), identifier: "acceptClaim")
        case .contestClaim:
            Spec(title: .disputesContestClaim, icon: .shieldCheck, busy: .answering(.contest), identifier: "contestClaim")
        case .pay, .confirmReceipt, .awaitingArrival, .openDispute, .cancel, .review: nil
        }
    }
}
