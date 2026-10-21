# Abbay

A simple, privacy-focused audiobook player built with SwiftUI. 100% native iOS implementation with zero third-party dependencies.

## Why Abbay?

This is a lightweight audiobook player that prioritizes your privacy:
- **No external dependencies** - Pure native Swift/SwiftUI implementation
- **No data collection** - Your listening habits stay on your device
- **Network only when you ask** - The app contacts librivox.org and archive.org solely to search, show and download public-domain audiobooks. It sends no identifiers and no listening data
- **No tracking or observability tools** - What you listen to is your business
- **Lightweight** - Minimal footprint, maximum performance

## Dependencies

This project uses [Xcodegen](https://github.com/yonaskolb/XcodeGen), [Fastlane](https://fastlane.tools/) and [Bundler](https://bundler.io/) to minimize setup time and ensure consistency across development environments. It also uses [Swiftlint](https://realm.github.io/SwiftLint/) to maintain code quality and consistency.

Please use **Xcode 26** to run this project. GitHub Actions is pinned to `26.0.1` on `macos-15`. The app's deployment target is **iOS 17.0** (iPhone). Tests use the simulator named in `.actions.yml`: `iPhone 17 (26.0)`.

Ruby is pinned to **3.2.0** via `.ruby-version`. The app version lives in the `version` file (currently `0.2.0` / build `2`).

### Why those tools?

[Xcodegen](https://github.com/yonaskolb/XcodeGen) is ideal for team collaboration as it eliminates the need to commit `.xcodeproj` and `.xcworkspace` files to version control. Instead, we use a configuration file (`project.yml`) that generates the Xcode project on the fly. This prevents merge conflicts and keeps the repository clean.

[Fastlane](https://fastlane.tools/) provides powerful automation for building, testing, and releasing. It consolidates common development tasks into simple lanes that can be run locally or in CI/CD pipelines.

[Bundler](https://bundler.io/) ensures all developers and CI environments use the same versions of Ruby dependencies, eliminating "works on my machine" issues.

[Swiftlint](https://realm.github.io/SwiftLint/) enforces consistent code style and best practices across the codebase.

## Setup

Although not required, it is recommended to use [rbenv](https://rbenv.org/) to manage your Ruby environment:

```bash
brew install rbenv
```

```bash
rbenv install 3.2.0
```

```bash
rbenv local 3.2.0
```

First, install dependencies with:
```bash
bundle install
```

Then generate and open the Xcode project:
```bash
bundle exec fastlane generate_project
```

The project will automatically open in Xcode. Press `Cmd+R` to build and run.

## Available Fastlane Commands

```bash
# Generate the Xcode project
bundle exec fastlane generate_project

# Open an already-generated project
bundle exec fastlane open_project

# Run tests
bundle exec fastlane test_project

# Generate a release build
bundle exec fastlane generate_app

# Run SwiftLint
bundle exec fastlane lint_project

# Stamp MARKETING_VERSION / CURRENT_PROJECT_VERSION from the version file
bundle exec fastlane update_version

# Clean build artifacts
bundle exec fastlane clean_project
```

Pass `open:false` to `generate_project`, `test_project`, or `generate_app` to skip opening the result.

## Features

- Import local audio files (Files picker, `UTType.audio`)
- Add public-domain audiobooks from LibriVox: search, browse, download, and start listening while chapters are still downloading (the vendored `NetworkProvider` module under `Modules/` is the only networking code)
- Audio playback with standard controls (play, pause, skip back/forward 15s and 30s)
- Chapter navigation (in-player list, next/previous chapter)
- Progress tracking via Core Data; security-scoped file bookmarks keep Files access after relaunch
- Lock Screen / Control Center / Now Playing (`MPRemoteCommandCenter`: play/pause, skip 15s, next/previous chapter, seek)
- CarPlay support (library list, Now Playing, chapters)
- Siri support:
  - App Intents (`AudioPlaybackIntent`) for resume, pause, next/previous chapter, play by name, play chapter
  - SiriKit `INPlayMediaIntent` via the `AbbayIntents` extension (media-domain routing, including title-only “play \<book\>”)
- Core Spotlight indexing of the library to help Siri match titles
- Dark mode support
- Localization support (String Catalog, source language English; Siri dialogs are English-only)
- Swipe-to-delete in the library

## Architecture

The app is built using SwiftUI with a clean architecture approach, separating concerns into distinct layers:
- **UI Layer**: SwiftUI views and view models
- **Domain Layer**: Business logic and use cases
- **Data Layer**: Local storage and file management

All audio playback is handled using AVFoundation, Apple's native framework for working with audiovisual media. Lock Screen / Control Center commands go through `NowPlayingManager`.

Siri is implemented in the app target (`Abbay/Intents`) and in the `AbbayIntents` SiriKit extension. Shared Siri state uses the App Group `group.com.edyuto.abbay`. Design notes live under `docs/superpowers/`.

`project.yml` generates four targets: **Abbay**, **AbbayTests**, **AbbayIntents**, and **AbbayIntentsTests**.

## GitHub Actions

We use custom GitHub Actions for CI/CD. The configuration can be adjusted via `.actions.yml`:

```yaml
run_swiftlint: true
run_tests: false
run_ui_tests: false
test_device: iPhone 17 (26.4)
```

**Which PRs run the suites on CI depends on the base branch.** The flags above enable the
macOS jobs, but those jobs also require the PR's base branch to be `main`:

| PR base | CI runs |
|---|---|
| `develop` | SwiftLint only |
| `main` | SwiftLint, unit suite, UI suite |

Each macOS job takes about 11 minutes and GitHub bills macOS runners at 10x the Linux rate, so
running them on every `develop` PR is not worth it. Release-bound PRs into `main` get the full
set, because that is where a pipeline break is most expensive. Set either flag to `false` as a
kill switch.

Since `develop` PRs get no suite run, **the suites are a local gate for day-to-day work.** Before
merging, run:

```bash
bundle exec fastlane verify
```

That runs SwiftLint `--strict`, the unit suite and the UI suite off a single build and fails on
the first problem -- about six minutes total.

Validate-branch runs on PRs into `main` or `develop`. Release-app runs on push to `main`
(simulator archive attached to a GitHub Release tagged from the `version` file). Both macOS jobs
run on `macos-26` with Xcode `26.4.1`.

Actions used:
* [Swiftlint](https://github.com/realm/SwiftLint/pkgs/container/swiftlint) (`0.59.1`)
* [Setup Xcode version](https://github.com/marketplace/actions/setup-xcode-version)
* [xcresulttool](https://github.com/marketplace/actions/xcresulttool)
* [Fastlane](https://fastlane.tools/)

## Contributing

Contributions are welcome! Please ensure all tests pass and SwiftLint validation succeeds before submitting a PR.

## License

This project is open source and available under the MIT License.
