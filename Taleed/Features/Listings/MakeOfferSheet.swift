import SwiftUI

/// "Faire une offre" (screens.md §7 G4, §2 G10 screen 1; website `listing-actions.tsx`): the hint
/// "Prix affiché : {price}…", the amount in DA with the server's bounds under it, and "Envoyer l'offre".
/// An amount outside `offerRange` shows `offers.errorRange` before anything is sent.
struct MakeOfferSheet: View {
    let price: Int
    let range: AmountRange
    /// Sends the amount; the sheet acts on the answer (`ListingDetailViewModel.makeOffer`).
    let send: (Int) async -> ListingDetailViewModel.OfferOutcome
    /// The sheet is done: close it and continue with the outcome (toast, conversation).
    let onFinish: (ListingDetailViewModel.OfferOutcome) -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        OfferAmountSheet(
            title: l10n.string(.offersMakeOffer),
            hint: l10n.format(.offersOfferHint, PriceFormatter.format(price, language: l10n.language)),
            range: range,
            submit: { amount in
                let outcome = await send(amount)
                switch outcome {
                case let .outOfRange(newRange?):
                    // The price changed: the new bounds, in red.
                    return .showRange(newRange)
                case .busy:
                    return .stay
                case .sent, .pending, .outOfRange(nil), .failed:
                    onFinish(outcome)
                    return .finish
                }
            },
            onClose: { onFinish(.busy) }
        )
    }
}
