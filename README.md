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

Please use **Xcode 27.1** to run this project. GitHub Actions is pinned to `27.1` on the `xcode-27` image. The app's deployment target stays **iOS 17.0** (iPhone): newer APIs, such as iOS 27's App Intents audio domain, are gated with `@available`. Tests use the simulator named in `.actions.yml`: `iPhone 17 (27.0)`, locally and on CI (install the runtime with `xcodebuild -downloadPlatform iOS -buildVersion 24A434`). The iOS 27.1 runtime only offers the iPhone Duo, a shorter screen with a side tab rail, where the suites also pass (#203); run it with `ABBAY_TEST_DEVICE='iPhone Duo (27.1)' bundle exec fastlane verify` (or `'iPhone 17 (26.4)'` for iOS 26). Select Xcode 27.1 first (`sudo xcode-select -s /Applications/Xcode-27.1.0.app`), since the iOS 27 code needs its SDK.

If another Xcode is selected with `xcode-select`, run commands with `DEVELOPER_DIR=/Applications/Xcode-27.1.0.app/Contents/Developer` rather than switching globally. Before merging, the suites also run on the older runtimes the app supports: the full suites on iOS 26.4, and the accessibility and cover UI tests on iOS 18.5 and 17.5.

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

# Generate a simulator release build (.xcarchive, no IPA)
bundle exec fastlane generate_app

# Archive, check, export an App Store IPA and upload to TestFlight (see "Releasing")
bundle exec fastlane release

# Run SwiftLint
bundle exec fastlane lint_project

# Stamp MARKETING_VERSION / CURRENT_PROJECT_VERSION from the version file
bundle exec fastlane update_version

# Clean build artifacts
bundle exec fastlane clean_project
```

Pass `open:false` to `generate_project`, `test_project`, or `generate_app` to skip opening the result.

## Releasing

`bundle exec fastlane release` produces and uploads a TestFlight build:

1. Picks the build number, generates the project and stamps the marketing version (first line
   of `version`) and that build number into the generated project (#183):
   - **With an API key:** `max(latest TestFlight build, version file) + 1`. The latest build is
     read with `latest_testflight_build_number` across all versions (an app with no builds reads
     as 0), so consecutive releases upload without editing `version`.
   - **Without a key:** the `version` file's build number, unchanged. That run never uploads, so
     it has nothing to collide with; the lane says the number was not checked. (A failure here
     would block the local IPA, and a timestamp or commit count would permanently inflate the
     numbers TestFlight then has to exceed.)
   - **`build_number:<n>`** overrides both; with a key the lane refuses, before archiving, a
     number that is not above TestFlight's latest.

   The lane never writes `version`: the chosen number lives only in the generated `.xcodeproj`,
   so `verify` and other local runs leave the file alone. `version` stays the marketing-version
   source (`fastlane update_version` stamps it); its build number is a floor, raised by hand only
   to jump ahead. `bundle exec fastlane release dry_run:true` resolves the key and the number,
   prints the plan and stops before building. The logic is `fastlane/build_number.rb`, tested by
   `ruby fastlane/test/build_number_test.rb` (also run by `verify`).
2. Archives Release for `generic/platform=iOS` to `build/Abbay.xcarchive`.
3. Runs `Scripts/check-app-binary` on the archived app (see below).
4. Exports `build/export/Abbay.ipa` with `fastlane/ExportOptions-AppStore.plist`
   (`app-store-connect`, automatic signing, symbols uploaded) and checks it again with
   `--require-distribution`.
5. Uploads the IPA with `upload_to_testflight`, authenticated with an App Store Connect API key.
   Without the key the lane stops after the IPA and says so, so it runs locally without one.

| Env var / secret | Value |
|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from App Store Connect › Users and Access › Integrations |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Issuer ID shown on the same page |
| `APP_STORE_CONNECT_API_KEY_KEY` | Contents of the `.p8` file (or set `APP_STORE_CONNECT_API_KEY_PATH` to its path) |

When the key is set the lane also passes it to `xcodebuild` (`-allowProvisioningUpdates`), so
Xcode can create the distribution certificate and App Store profiles without a signed-in
account. Without it, the export uses the account signed in to Xcode › Settings › Accounts.
`fastlane/Appfile` holds the bundle id and team; an Apple ID is never committed (set
`FASTLANE_APPLE_ID` if an action needs one).

`Scripts/check-app-binary <.app | .xcarchive | .ipa>` works on any build, including the OTA test
builds (pass `--allow-debug-resources` for Debug builds, which carry the UI-test audio fixture).
It fails when:

- any Mach-O in the app links a path other than `@rpath`, `@executable_path`, `@loader_path`,
  `/usr/lib` or `/System` (the launch crash fixed in #142);
- the signed app lacks CarPlay audio, Siri or the App Group `group.com.edyuto.abbay`, or an app
  extension lacks the App Group (also checked in the embedded profile);
- a Debug-only resource such as `Christmastide.m4b` ships;
- with `--require-distribution`, the build is development-signed or its profile lists devices.

**Owner steps before the first upload** (#111):

1. Sign in again under Xcode › Settings › Accounts (the stored token has expired), or rely on
   the API key below.
2. Create an App Store Connect API key (App Manager or Admin role; Admin is needed for Xcode to
   create the distribution certificate itself), keep the `.p8`, and add the three values above
   as repository secrets.
3. Run `bundle exec fastlane release` once locally and confirm the `.ipa` check passes: it is the
   first distribution-signed build, and the App Group must reach the profiles of both the app
   and `AbbayIntents` (`AppGroup.swift` crashes at launch without it).

`release-app.yml` runs the lane on every push to `main`. With the secrets it uploads to
TestFlight and attaches the IPA and dSYMs to a GitHub Release tagged from the `version` file;
without them it builds the simulator archive instead and warns.

## Features

- Import local audio files (Files picker, `UTType.audio`)
- Add public-domain audiobooks from LibriVox: search, browse, download, and start listening while chapters are still downloading (networking is limited to librivox.org and archive.org: API requests, chapter downloads and cover images go through the vendored `NetworkProvider` module under `Modules/`, and streaming uses AVPlayer. The cover loader refuses any other host and caches covers in memory and on disk)
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
test_device: iPhone 17 (27.0)
ci_test_device: iPhone 17 (27.0)
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
(see "Releasing": TestFlight upload when the secrets are set, simulator archive otherwise). Both macOS jobs
run on the `xcode-27` image (a GitHub preview label, macOS 27) with Xcode `27.1`.

Actions used:
* [Swiftlint](https://github.com/realm/SwiftLint/pkgs/container/swiftlint) (`0.59.1`)
* [Setup Xcode version](https://github.com/marketplace/actions/setup-xcode-version)
* [xcresulttool](https://github.com/marketplace/actions/xcresulttool)
* [Fastlane](https://fastlane.tools/)

## Contributing

Contributions are welcome! Please ensure all tests pass and SwiftLint validation succeeds before submitting a PR.

## License

This project is open source and available under the MIT License.
