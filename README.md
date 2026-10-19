# Taleed iOS

The iOS app of [Taleed](https://taleed.app), the second-hand marketplace for Algeria.
Swift 6, SwiftUI, iOS 17 and later, iPhone in portrait.

## Requirements

- Xcode 16 or later (tested with Xcode 26.0.1).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), only to change the project:
  `brew install xcodegen`.
- [SwiftLint](https://github.com/realm/SwiftLint): `brew install swiftlint`.
- [openapi-generator](https://openapi-generator.tech), only to regenerate the API client:
  `brew install openapi-generator` (tested with 7.26.0).

## Project layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen spec. `Taleed.xcodeproj` is generated from it and committed. |
| `Config/*.xcconfig` | Build configurations: bundle ID, app name, API base URL. |
| `Taleed/App` | Entry point, dependency container, root view, theme. |
| `Taleed/Core` | Networking, session, token storage, launch flow, languages. |
| `Taleed/Features` | Screens and their view models. |
| `Taleed/Resources` | `Localizable.xcstrings` (fr, ar, en) and assets. |
| `TaleedAPI/` | API client generated from `api/openapi.json`. Never edit it. |
| `TaleedTests/` | Unit tests (Swift Testing). |

## Shared screen infrastructure

What every screen group reuses (screens.md §0 and §1, api-guide.md):

| Piece | Where |
|---|---|
| Router: tabs, per-tab stacks, links, pushes, payment return, auth gate, website pages | `Core/Navigation/AppRouter.swift`, `AppRoute.swift`, `LinkRouter.swift`; screens per route in `Features/Shell/RouteDestinationView.swift` |
| Calling the API: errors, read retries with backoff, rate-limit pause, rejected token | `Core/Networking/ApiCaller.swift`, `TaleedApi.swift` (add a protocol per screen group, implemented in an extension of `GeneratedTaleedApi`) |
| Error codes and their messages | `Core/Networking/ApiError.swift`, `ApiErrorMessages.swift`; states in `Features/Shell/StateViews.swift`, toasts in `Features/Shared/AppToasts.swift` |
| Cursor pagination, de-duplicated by id, pull-to-refresh | `Core/Lists/PagedList.swift`, `Features/Shared/PagedListView.swift` |
| Catalog cached on disk, refreshed at launch and on language switch | `Core/Catalog/` |
| Images (Nuke, disk cache) | `Core/Images/ImageLoading.swift`, `Features/Shared/RemoteImage.swift` |
| Photo uploads (`POST /uploads`) | `Core/Uploads/PhotoUpload.swift` |
| In-app browser | `Core/Navigation/InAppBrowser.swift` (`router.openWebsite(.terms)`) |
| Developer menu (debug builds only) | `Features/Developer/DeveloperMenuView.swift` (Settings → Developer menu) |
| Listing cards: `GET /listings` (`ListingsApi`, `ListingSearchParameters`), the card model `ListingSummary`, the card and two-column grid (`ListingCardView`, `ListingGrid`) | `Features/Listings/`, `Core/Models/Listing.swift` |
| Explore (G3): the tab's search field and category tree, search results with filter chips, the filter and sort sheets, search by photo and its results; `ExploreApi` (`GET /brands`, `GET /sizes`, `POST`/`GET /visual-searches`), brands and sizes in `ExploreReferenceStore` | `Features/Explore/` |
| Listing detail (G4): the Item Detail screen with its sticky offer / buy bar and the tab bar inside it, owner bar (edit, hide / resume, delete), status notices, offer sheet, bundle toggle, full-screen photos, share; `ListingDetailApi` (`GET /listings/{id}`, `POST /conversations`, `POST /listings/{id}/offers`, `POST /listings/{id}/status`, `DELETE /listings/{id}`, `GET /bundles/{id}`, `PUT /members/{username}/bundle`) | `Features/Listings/` |
| Report sheet (G19, shared): reasons from the catalog, details, up to 3 screenshots; `ReportsApi` (`POST /reports`) | `Features/Safety/` |
| Member profile (G5): header on the seller card, follow, block / unblock with its confirmation, report (shared sheet), the wardrobe with its filter sheet and the reviews; `MembersApi` (`GET /members/{username}`, its `listings` and `reviews`, `PUT`/`DELETE …/follow`, `PUT`/`DELETE …/block`). Pushed screens reserve the tab bar's height (`MainShellView`) | `Features/Members/` |
| Hearts shared by every screen: optimistic, reverts on failure, `404` removes the card, sign-in first when signed out; a card loaded after the change shows the server's state again; every confirmed change is logged in `changes` for the favorites screen (`FavoriteStore`, in the environment) | `Features/Listings/FavoriteStore.swift` |
| Favorites (G6): the product grid of `GET /me/favorites` with its count, empty state and undo toast; follows the shared hearts (hearted elsewhere joins the top, un-hearted leaves at once) and walks back from the top when a change moved the API's position cursors; `FavoritesListApi` | `Features/Favorites/` |
| Sell (G7): the Sell tab's form (Figma "Sell an Item"): photos uploaded as they are picked with a retry per photo, cover and removal; title, description, category then subcategory, brand (catalog or typed), size with suggestions, condition, price, shipping wilaya prefilled from the profile; checks on the device, the API's field errors by path, then the new listing. `SellApi` (`POST /listings`); brands and sizes from `ExploreReferenceStore`. Tab roots also reserve the tab bar's height now (`MainShellView`) | `Features/Sell/` |
| Messages (G9): the Messages tab's inbox (`GET /conversations`, Tous / Achats / Ventes filter, quiet reload on return), the conversation (header, item strip, menu with report and block, bubbles, pills, offer and bundle cards without their G10 buttons, official announcements' HTML drawn natively, composer with one photo, optimistic sending with `clientId` and "Réessayer", read marks that update the tab badge); live updates through the SSE reader `ConversationEventsSource` (`GET /conversations/{id}/events`, reconnects with `Last-Event-ID`). `MessagesApi`, `MessagesDependencies` | `Features/Messages/` |
| Offers and bundles (G10): the conversation's pinned offer card (Accepter with a confirmation, Refuser, Contre-offre, Annuler l'offre, Payer maintenant, from the offer's `can…` flags), "Faire une offre" / "Proposer un prix" above the composer, one offer-amount bottom sheet for the listing, conversation, counter and bundle offers (`OfferAmountSheet`); the bundle builder (`.bundleBuilder`, the wardrobe with Ajouter / Retirer, preselected from `openBundleId`, kept in memory until "Voir le lot") and the bundle review (`/bundle/{id}`: items with Retirer, unavailable notice, accepted offer, the server's summary, offer, buy, ask the seller). `OffersApi` (`POST /conversations/{id}/offers`, `/offers/{id}/accept|decline|counter|cancel`), `BundlesApi` (`GET /bundles/{id}`, `PUT /members/{username}/bundle`, `POST /bundles/{id}/offers`, `POST /bundles/{id}/ask`), `BundleDependencies` | `Features/Offers/`, `Features/Bundles/` |
| Checkout and payment return (G11): the Buy Now screen (`.checkout`, no tab bar): goods (listing or bundle), delivery kind with both fees ("jusqu'à" until a commune), saved address, recipient and phone checks, wilaya / commune / desk pickers, the server's summary, promo code, wallet switch, payment methods from the quote, and the button; a quote on every change the price depends on, `POST /orders` once per tap with its `clientId` (sent again after a lost answer), `price_changed` / `promo_invalid` / `payment_method_unavailable` / field issues handled; the gateway's page in an ephemeral `WebAuthenticationSession`, then the payment screen (`.orderPayment`, also for `taleed://payment-return` and for the buyer's own order that holds the goods) that syncs and shows the result, "Payer maintenant" and "Enregistrer cette adresse". `CheckoutApi`, `CheckoutDependencies`; `AppRouter.replace(_:with:)` | `Features/Checkout/` |
| Orders, buyer side (G12): the orders list (`.orders`, Profile → Commandes; tabs Achats / Ventes with the server's counts, paged), the order screen (`.order`: status, notices, dispute card, goods and the other member, the buyer's buttons from `actions` only — Payer maintenant through the gateway then a sync, Confirmer la réception and Annuler la commande after a confirmation, the disabled state while the parcel travels, Signaler un problème, Laisser une évaluation — amounts, delivery and tracking, timeline with the carrier's scans, reviews), the dispute form and review form sheets, and the dispute thread (`.dispute`, composer with up to 4 photos). `OrdersApi`, `OrdersDependencies`; `OrderChangeCenter` updates the list after an action. | `Features/Orders/` |
| Orders, seller side (G13): on a sale, the seller's buttons from `actions` only — Bordereau d'expédition after a confirmation (`POST /orders/{id}/ship`, then the label in the in-app browser; a `carrier_error` stays under the buttons with the carrier's `detail`), Imprimer le bordereau (a fresh `GET /orders/{id}/label` on each tap), Générer le vrai bordereau (test servers), Accepter la réclamation after a confirmation and Contester (`POST /disputes/{id}/respond`, also in the dispute thread while `canRespond`). `SellerOrderButton`; `-TaleedDebugOrder carrier` shows a carrier refusal | `Features/Orders/` |
| Push registration: the permission asked after the member's first message or offer, then `POST /devices`, only when `features.push` (`false` locally). **Deferred:** the Firebase token source (SDK and `GoogleService-Info.plist`, plan action 3) comes with G16, with the push switch and the registration after sign-in and a language switch; until then nothing is asked | `Core/Push/PushRegistration.swift` |

Links can be tried on the simulator with the app's scheme, which reads like a path:
`xcrun simctl openurl booted "taleed://ar/orders/<id>"`, or with the launch argument
`-TaleedDebugOpenURL /listings/<id>`.

## Build configurations

| Configuration | Bundle ID | App name | API |
|---|---|---|---|
| Debug | `app.taleed.debug` | Taleed Dev | `http://localhost:3000/api/v1` (plain HTTP allowed for local hosts only) |
| Release | `app.taleed` | Taleed | `https://taleed.app/api/v1` |

To add a configuration such as Staging: create `Config/Staging.xcconfig` (include
`Base.xcconfig`, set `TALEED_API_BASE_URL`), add it under `configs` and `configFiles` in
`project.yml`, then run `xcodegen generate`.

## Run against the local backend

1. Start the backend in the `taleed` repository (`npm run db:up`, then `npm run dev`).
   Check it with `curl http://localhost:3000/api/health`.
2. Open `Taleed.xcodeproj`, pick the `Taleed` scheme and an iPhone simulator, and run.
   The Debug build calls `http://localhost:3000/api/v1`.

From the command line:

```bash
xcodebuild -project Taleed.xcodeproj -scheme Taleed -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Tests and lint

```bash
xcodebuild test -project Taleed.xcodeproj -scheme Taleed \
  -destination 'platform=iOS Simulator,name=iPhone 17'
swiftlint lint --strict
```

CI (`.github/workflows/ci.yml`) runs both on every pull request, builds Debug and Release, and
checks that `Taleed.xcodeproj` matches `project.yml`.

## Regenerate the API client

The contract is `api/openapi.json`, a copy of `docs/mobile/openapi.json` from the backend
repository. To take the latest contract and regenerate `TaleedAPI/`:

```bash
scripts/generate-api.sh --from ../taleed
```

Without `--from`, the script regenerates from the copy in `api/`. Commit the contract and the
generated code together. If the compiler then points at a `switch` that must handle a new
value, handle it.

## Design system

The Figma design system lives in `Taleed/DesignSystem`:

| Path | What |
|---|---|
| `Tokens/TaleedTokens.swift` | Colours, text styles, spacing, radius, elevation, opacity, sizes, layout and motion, named as in the design hand-off's `tokens.json` (`TaleedColor.brandPrimary`, `TaleedFont.title1`, `TaleedSpacing.s16`, `TaleedRadius.m`). Generated. |
| `Icons/TaleedIcon.swift` | The 55 Phosphor icons (`TaleedIconView(.heart, size: 20, color: …)`). Generated. |
| `Foundation/` | Text-style modifier (`.taleedFont(TaleedFont.bodyRegular)`: Plus Jakarta Sans in every language, Alexandria as the cascade for Arabic script), shadows, images, price formatting (DA suffix), condition codes. `Theme` is the one entry point. |
| `Components/` | Buttons, fields, chips, tags, cards, checkout controls, app bars, bottom navigation, sheets, toasts… They take plain data and closures. |
| `Gallery/` | Debug-only gallery of every component (Settings → Design system). |

Assets are in `Resources/DesignSystem.xcassets` (icons as template SVGs) and the fonts in
`Resources/Fonts` (Plus Jakarta Sans and Alexandria, SIL Open Font License, licenses included).
Never edit the generated files: change `tokens.json` and run

```bash
scripts/generate-design-system.py --design ../design
```

Debug builds accept launch arguments that open a screen directly (for screenshots): see
`Gallery/DebugLaunchOptions.swift`.

## Change the project

Edit `project.yml`, then run `xcodegen generate` and commit `project.yml` and
`Taleed.xcodeproj` together. Do not edit the project only in Xcode: the next generation
would lose the change, and CI fails when the two differ.
