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
