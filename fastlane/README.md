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

### ios ui_test_project

```sh
[bundle exec] fastlane ios ui_test_project
```

Runs the UI test suite

Drives the real app in the simulator. Kept in its own lane and its own scheme because UI tests
boot the app and are far slower than the unit suite -- `test_project` must stay quick.

#### Optional parameters
  * open: true - Open the test results after running tests

### ios verify

```sh
[bundle exec] fastlane ios verify
```

Full pre-merge verification: SwiftLint, unit tests, UI tests

CI does not run the test suites (see .actions.yml), so this is the gate before merging. It
generates the project once and reuses that build for both suites, rather than letting
`test_project` and `ui_test_project` each clean and rebuild.

### ios generate_app

```sh
[bundle exec] fastlane ios generate_app
```

Generate app (xcarchive)

#### Optional parameters
  * open: true - Open the archive after generation

### ios release

```sh
[bundle exec] fastlane ios release
```

Archives a Release build, checks it, exports an App Store .ipa and uploads it to TestFlight

1. Generates the project and stamps the version from the `version` file.
2. Archives Release for `generic/platform=iOS` to build/Abbay.xcarchive.
3. Runs Scripts/check-app-binary on the archived .app: load paths (#142), entitlements, no
   Debug-only resources.
4. Exports build/export/Abbay.ipa with fastlane/ExportOptions-AppStore.plist and checks it again (the
   export re-signs with the distribution profile, which is what users get).
5. Uploads to TestFlight with an App Store Connect API key. Without the key env vars the lane
   stops after the .ipa with a message, so it is runnable locally.

Env: APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_KEY_ISSUER_ID, and
APP_STORE_CONNECT_API_KEY_KEY (.p8 contents) or APP_STORE_CONNECT_API_KEY_PATH (.p8 path).

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
