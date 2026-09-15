# Abbay

A privacy-focused audiobook player for iPhone, built with SwiftUI. Native iOS only — no SPM, CocoaPods, or analytics SDKs.

Current version: **0.2.0** (see the `version` file).

## Why Abbay?

- **No app-store dependencies** — playback, storage, Siri, and CarPlay all use Apple frameworks
- **No data collection** — the library and listening position stay on device
- **No tracking** — diagnostic logs used for Siri routing stay local
- **Local files** — import audio from Files; nothing is streamed from a catalog

## Requirements

- macOS with [Xcode 16.2](https://developer.apple.com/xcode/)
- iOS **17.0+** (iPhone; `TARGET_DEVICE_FAMILY` is `1`)
- Ruby **3.2.0** (for Fastlane / Bundler)

Although not required, [rbenv](https://rbenv.org/) is the recommended way to pin Ruby:

```bash
brew install rbenv
rbenv install 3.2.0
rbenv local 3.2.0
```

## Setup

```bash
bundle install
bundle exec fastlane generate_project
```

That generates `Abbay.xcodeproj` from `project.yml` (via the vendored `Scripts/xcodegen` binary), stamps the version from the `version` file, and opens Xcode. Press `Cmd+R` to run.

The `.xcodeproj` is gitignored. Do not commit it.

## Features

- Import local audio files (multi-select document picker, `UTType.audio`)
- Playback with play/pause, skip back/forward 15s and 30s
- Chapter list and skip to next/previous chapter
- Progress persisted in Core Data (including security-scoped bookmarks so Files access survives relaunch)
- Lock Screen / Control Center / Now Playing metadata via `MPRemoteCommandCenter`
- CarPlay audio scene: library list, Now Playing, chapter list
- Siri:
  - App Intents (`AudioPlaybackIntent`) for play/pause, next/previous chapter, play by name, play chapter
  - SiriKit `INPlayMediaIntent` via the `AbbayIntents` app extension (media-domain routing, including one-shot “play \<title\> on Abbay”)
- Core Spotlight indexing of the library to help Siri match titles
- Dark UI (forced `preferredColorScheme(.dark)`)
- String Catalog localization (`Localizable.xcstrings`) for in-app copy; Siri dialogs are English-only for now

Not currently in the app: playback-speed control, sleep timer, or user-created bookmarks.

## Architecture

SwiftUI on top of a small layered stack:

| Layer | Location | Role |
| --- | --- | --- |
| UI | `Abbay/View` | Screens and view models |
| Domain | `Abbay/Model` | Models, use cases, repositories |
| Data | `Abbay/Core/Data` | Core Data stack and local storage |
| Playback | `Abbay/Core/Player`, `NowPlayingManager` | `AVFoundation` player + Now Playing |
| Voice | `Abbay/Intents`, `AbbayIntents` | App Intents in the app target; SiriKit extension for `INPlayMediaIntent` |

Shared Siri state (last played, library snapshot, launch-unavailable flag) lives in the App Group `group.com.edyuto.abbay`.

`DependencyContainer` is configured at launch and is the single entry point for the live `Player`. Combine publishers replace manual observers for playback time and “now playing” URL.

Siri design notes, plans, and research live under `docs/superpowers/`.

## Targets

Generated from `project.yml`:

- **Abbay** — application
- **AbbayTests** — app unit tests
- **AbbayIntents** — SiriKit intents extension
- **AbbayIntentsTests** — extension unit tests (sources are compiled into the test bundle; an app-extension binary cannot be linked as a test host)

## Tooling

[XcodeGen](https://github.com/yonaskolb/XcodeGen) keeps the Xcode project out of git. The source of truth is `project.yml`; a vendored generator lives at `Scripts/xcodegen`.

[Fastlane](https://fastlane.tools/) wraps generate / test / archive / lint. [Bundler](https://bundler.io/) pins the Ruby gems (`fastlane`, `xcodeproj`, `yaml`). `Gemfile.lock` is gitignored; `.ruby-version` is `3.2.0`.

[SwiftLint](https://realm.github.io/SwiftLint/) runs from `Scripts/swiftlint` on local builds (Xcode build phase + `lint_project` lane) and in CI via the official container.

### Fastlane lanes

```bash
# Generate the Xcode project (opens Xcode unless open:false)
bundle exec fastlane generate_project

# Open an already-generated project
bundle exec fastlane open_project

# Run tests (uses test_device from .actions.yml)
bundle exec fastlane test_project

# Generate a simulator Release archive
bundle exec fastlane generate_app

# Run SwiftLint
bundle exec fastlane lint_project

# Stamp MARKETING_VERSION / CURRENT_PROJECT_VERSION from the version file
bundle exec fastlane update_version

# Remove generated projects and build artifacts
bundle exec fastlane clean_project
```

Pass `open:false` to `generate_project`, `test_project`, or `generate_app` to skip opening the result.

The `version` file is two lines: marketing version, then build number. `Scripts/postinstall` (XcodeGen `postGenCommand`) applies it after project generation.

## GitHub Actions

CI is configured in `.github/workflows/` and toggled from `.actions.yml`:

```yaml
run_swiftlint: true
run_tests: false
test_device: iPhone 16
```

- **Validate branch** (PRs into `main` or `develop`): SwiftLint is on. Unit tests are currently **off** (`run_tests: false`) to keep Actions time down; run `bundle exec fastlane test_project open:false` locally before merging.
- **Release .app** (push to `main`): builds a simulator archive with Fastlane and attaches `App.zip` to a GitHub Release tagged from the `version` file.

Actions used:

- [SwiftLint container](https://github.com/realm/SwiftLint/pkgs/container/swiftlint) `0.59.1`
- [Setup Xcode version](https://github.com/marketplace/actions/setup-xcode-version) `16.2`
- [xcresulttool](https://github.com/marketplace/actions/xcresulttool)
- [Fastlane](https://fastlane.tools/)

## Contributing

Contributions are welcome. Before opening a PR against `develop`:

1. Generate the project and run tests locally
2. Keep SwiftLint clean (`bundle exec fastlane lint_project`)
3. Do not commit `.xcodeproj`, `.xcworkspace`, or `DerivedData`

## License

This project is open source and available under the MIT License.
