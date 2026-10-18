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

## Change the project

Edit `project.yml`, then run `xcodegen generate` and commit `project.yml` and
`Taleed.xcodeproj` together. Do not edit the project only in Xcode: the next generation
would lose the change, and CI fails when the two differ.
