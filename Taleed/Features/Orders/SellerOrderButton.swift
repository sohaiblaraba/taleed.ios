import SwiftUI

/// A seller's button on the order screen (screens.md §2 G13, §7 G12/G13 "Buttons and confirmations";
/// website `order-actions.tsx`): "Bordereau d'expédition", "Imprimer le bordereau", "Générer le vrai
/// bordereau", "Accepter la réclamation", "Contester". The first button of the screen is the main one
/// (mint, decision D-10); a running action shows its spinner and keeps the others still. The label
/// requests take several seconds, so their spinner keeps a label that says what runs ("Génération du
/// bordereau…").
struct SellerOrderButton: View {
    let action: OrderRules.MemberAction
    let isFirst: Bool
    let busy: OrderDetailViewModel.Busy?
    let perform: (OrderRules.MemberAction) -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        if let spec {
            let isRunning = busy == spec.busy
            let title = isRunning ? spec.runningTitle.map(l10n.string) : nil
            TaleedButton(title: title ?? l10n.string(spec.title), kind: isFirst ? .secondary : .outline, size: .large,
                         leadingIcon: spec.icon, isLoading: isRunning, isFullWidth: true,
                         keepsLabelWhileLoading: spec.runningTitle != nil) {
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
        /// What the button says while it runs, for the slow ones.
        var runningTitle: L10nKey?
    }

    private var spec: Spec? {
        switch action {
        case .ship:
            Spec(title: .ordersGetShippingLabel, icon: .truck, busy: .shipping, identifier: "ship",
                 runningTitle: .appOrderGeneratingLabel)
        // The printer, as in the label sheet.
        case .printLabel:
            Spec(title: .ordersDownloadLabel, icon: .printer, busy: .printing, identifier: "printLabel",
                 runningTitle: .appOrderOpeningLabel)
        case .replaceTestLabel:
            Spec(title: .ordersGetRealShippingLabel, icon: .truck, busy: .shipping, identifier: "replaceTestLabel",
                 runningTitle: .appOrderGeneratingLabel)
        case .acceptClaim:
            Spec(title: .disputesAcceptClaim, icon: .checkCircle, busy: .answering(.accept), identifier: "acceptClaim")
        case .contestClaim:
            Spec(title: .disputesContestClaim, icon: .shieldCheck, busy: .answering(.contest), identifier: "contestClaim")
        case .pay, .confirmReceipt, .awaitingArrival, .openDispute, .cancel, .review: nil
        }
    }
}
