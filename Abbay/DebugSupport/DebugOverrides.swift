//
//  DebugOverrides.swift
//  Abbay
//

import Foundation

/// The one place app code asks whether a launch argument swapped a dependency for a UI-test
/// stand-in. Production call sites read `DebugOverrides.x() ?? real`.
///
/// Compiled into every configuration so those call sites need no `#if`, but each body is
/// `#if DEBUG`, so in Release every override is `nil`. The stand-ins themselves (`UITest*.swift`
/// in this folder) are left out of Release by `EXCLUDED_SOURCE_FILE_NAMES` in `project.yml`.
enum DebugOverrides {
    /// Seeds or empties the library for `-seedLibrary` / `-resetLibrary`. Does nothing in Release.
    static func runLaunchSeeding(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        UITestSeeder.run(arguments: arguments)
        #endif
    }

    /// A download manager that downloads nothing, for `-stubLibriVox`.
    static func downloadManager(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> BookDownloadManagerProtocol? {
        #if DEBUG
        if arguments.contains(LaunchArgument.stubLibriVox) {
            return UITestDownloadManager()
        }
        #endif
        return nil
    }

    /// An in-memory catalog, for `-stubLibriVox`.
    static func libriVoxClient(arguments: [String] = ProcessInfo.processInfo.arguments) -> LibriVoxClientProtocol? {
        #if DEBUG
        if arguments.contains(LaunchArgument.stubLibriVox) {
            return UITestLibriVoxClient()
        }
        #endif
        return nil
    }

    /// A short search debounce, so UI tests against the stub catalog don't wait.
    static func searchDebounce(arguments: [String] = ProcessInfo.processInfo.arguments) -> Duration? {
        #if DEBUG
        if arguments.contains(LaunchArgument.stubLibriVox) {
            return .milliseconds(50)
        }
        #endif
        return nil
    }
}
