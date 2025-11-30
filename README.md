# Abbay

A simple, privacy-focused audiobook player built with SwiftUI. 100% native iOS implementation with zero third-party dependencies.

## Why Abbay?

This is a lightweight audiobook player that prioritizes your privacy:
- **No external dependencies** - Pure native Swift/SwiftUI implementation
- **No data collection** - Your listening habits stay on your device
- **No tracking or observability tools** - What you listen to is your business
- **Lightweight** - Minimal footprint, maximum performance

## Dependencies

This project uses [Xcodegen](https://github.com/yonaskolb/XcodeGen), [Fastlane](https://fastlane.tools/) and [Bundler](https://bundler.io/) to minimize setup time and ensure consistency across development environments. It also uses [Swiftlint](https://realm.github.io/SwiftLint/) to maintain code quality and consistency.

Please use `Xcode 16.2` to run this project.

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

# Run tests
bundle exec fastlane test_project

# Generate a release build
bundle exec fastlane generate_app

# Run SwiftLint
bundle exec fastlane lint_project

# Clean build artifacts
bundle exec fastlane clean_project
```

## Features

- Audio playback with standard controls (play, pause, skip, rewind)
- Playback speed control
- Sleep timer
- Chapter navigation
- Bookmark support
- Progress tracking
- Dark mode support
- Localization support

## Architecture

The app is built using SwiftUI with a clean architecture approach, separating concerns into distinct layers:
- **UI Layer**: SwiftUI views and view models
- **Domain Layer**: Business logic and use cases
- **Data Layer**: Local storage and file management

All audio playback is handled using AVFoundation, Apple's native framework for working with audiovisual media.

## GitHub Actions

We use custom GitHub Actions for CI/CD. The configuration can be adjusted via `.actions.yml`:

```yaml
run_swiftlint: true
run_tests: true
test_device: iPhone 16
```

Actions used:
* [Swiftlint](https://github.com/realm/SwiftLint/pkgs/container/swiftlint)
* [Setup Xcode version](https://github.com/marketplace/actions/setup-xcode-version)
* [xcresulttool](https://github.com/marketplace/actions/xcresulttool)
* [Fastlane](https://fastlane.tools/)

## Contributing

Contributions are welcome! Please ensure all tests pass and SwiftLint validation succeeds before submitting a PR.

## License

This project is open source and available under the MIT License.
