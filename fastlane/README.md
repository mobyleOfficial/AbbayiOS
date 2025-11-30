fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios generate_project

```sh
[bundle exec] fastlane ios generate_project
```

Generates the project

#### Optional parameters
  * open: true - Open the project after generation

### ios open_project

```sh
[bundle exec] fastlane ios open_project
```

Opens the project

### ios test_project

```sh
[bundle exec] fastlane ios test_project
```

Tests the project

#### Optional parameters
  * open: true - Open the test results after running tests

### ios generate_app

```sh
[bundle exec] fastlane ios generate_app
```

Generate app (xcarchive)

#### Optional parameters
  * open: true - Open the archive after generation

### ios clean_project

```sh
[bundle exec] fastlane ios clean_project
```

Clean build artifacts

### ios update_version

```sh
[bundle exec] fastlane ios update_version
```

Updates the project version based on version file

### ios lint_project

```sh
[bundle exec] fastlane ios lint_project
```

Run swiftlint

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
