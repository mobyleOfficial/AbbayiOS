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

    /// A download manager that downloads nothing, for `-stubLibriVox`; with `-stubDownloadStates`
    /// it publishes a fixed state for every book it is given.
    static func downloadManager(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> BookDownloadManagerProtocol? {
        #if DEBUG
        if arguments.contains(LaunchArgument.stubLibriVox) {
            return UITestDownloadManager(publishesStates: arguments.contains(LaunchArgument.stubDownloadStates))
        }
        #endif
        return nil
    }

    /// An in-memory catalog, for `-stubLibriVox`.
    static func libriVoxClient(arguments: [String] = ProcessInfo.processInfo.arguments) -> LibriVoxClientProtocol? {
        #if DEBUG
        if arguments.contains(LaunchArgument.stubLibriVox) {
            let stubsCovers = arguments.contains(LaunchArgument.stubCovers)
            return UITestLibriVoxClient(
                coverURL: stubsCovers ? UITestCoverNetwork.coverURL : nil,
                isLarge: arguments.contains(LaunchArgument.stubDownloadStates),
                isSlow: arguments.contains(LaunchArgument.stubSlowLibriVox)
            )
        }
        #endif
        return nil
    }

    /// A fixed network path, for `-stubPathCellular`, `-stubPathHotspot`, `-stubPathLowDataMode` or
    /// `-stubPathOffline` (the first one given wins).
    static func networkPath(arguments: [String] = ProcessInfo.processInfo.arguments) -> NetworkPathProviding? {
        #if DEBUG
        let paths = [
            (LaunchArgument.stubPathCellular, UITestNetworkPath.cellular),
            (LaunchArgument.stubPathHotspot, UITestNetworkPath.hotspot),
            (LaunchArgument.stubPathLowDataMode, UITestNetworkPath.lowDataMode),
            (LaunchArgument.stubPathOffline, UITestNetworkPath.offline)
        ]
        if let match = paths.first(where: { arguments.contains($0.0) }) {
            return UITestNetworkPath(match.1)
        }
        #endif
        return nil
    }

    /// A cover loader over an in-memory network and its own disk cache, for `-stubCovers`. Emptied
    /// at launch unless `-stubCoversOffline`, whose network fails every request.
    static func coverLoader(arguments: [String] = ProcessInfo.processInfo.arguments) -> AsyncImageLoader? {
        #if DEBUG
        if arguments.contains(LaunchArgument.stubCovers) {
            let offline = arguments.contains(LaunchArgument.stubCoversOffline)
            let disk = CoverDiskCache(directory: UITestCoverNetwork.diskDirectory)
            if !offline { disk.removeAll() }
            return AsyncImageLoader(network: UITestCoverNetwork(isOffline: offline), diskCache: disk)
        }
        #endif
        return nil
    }

    /// Files *Import file* imports instead of presenting the picker: for `-stubFailingImport`, two
    /// that don't exist, so the real `FileLoader` fails on both; for `-stubMovedImport`, *Seeded
    /// Missing Book*'s file where it moved to.
    static func importURLs(arguments: [String] = ProcessInfo.processInfo.arguments) -> [URL]? {
        #if DEBUG
        if arguments.contains(LaunchArgument.stubMovedImport) {
            return [UITestSeeder.movedMissingFile()]
        }
        if arguments.contains(LaunchArgument.stubFailingImport) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("missing", isDirectory: true)
            return ["Missing Book.mp3", "Broken Book.m4b"].map { directory.appendingPathComponent($0) }
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

    /// A fresh in-memory settings store, for `-resetSettings`; with `-seedReadAlong`, Read-along is
    /// on in it. Never the real preferences: a UI test must not leave the feature on for the user.
    static func settingsStore(arguments: [String] = ProcessInfo.processInfo.arguments) -> KeyValueStoring? {
        #if DEBUG
        if arguments.contains(LaunchArgument.resetSettings) {
            let store = InMemoryKeyValueStore()
            if arguments.contains(LaunchArgument.seedReadAlong) {
                store.set(true, forKey: AppSettings.Key.readAlongEnabled)
            }
            return store
        }
        #endif
        return nil
    }

    /// A transcript store in the temporary directory, emptied here, at launch, whenever the stub
    /// engine is in use (`-seedReadAlong`, `-stubReadAlongEngine`): the canned text is this launch's
    /// only, like the settings under `-resetSettings`.
    static func readAlongStore(arguments: [String] = ProcessInfo.processInfo.arguments) -> ReadAlongStore? {
        #if DEBUG
        if usesStubReadAlongEngine(arguments) {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("UITestReadAlong", isDirectory: true)
            let store = ReadAlongStore(root: root)
            store.deleteAll()
            return store
        }
        #endif
        return nil
    }

    /// The canned-text transcriber, for `-stubReadAlongEngine` and `-seedReadAlong`.
    static func readAlongTranscriber(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> ReadAlongTranscribing? {
        #if DEBUG
        if usesStubReadAlongEngine(arguments) {
            return StubReadAlongTranscriber()
        }
        #endif
        return nil
    }

    /// `-seedReadAlong` implies `-stubReadAlongEngine`.
    private static func usesStubReadAlongEngine(_ arguments: [String]) -> Bool {
        arguments.contains(LaunchArgument.seedReadAlong) || arguments.contains(LaunchArgument.stubReadAlongEngine)
    }

    /// True for a UI test's launch (any `LaunchArgument`): the app then doesn't ask for Siri
    /// authorization. On a fresh simulator that system alert comes up a moment after launch, and
    /// a tap landing just as it appears goes to the alert instead of the app: XCTest dismisses an
    /// alert only if it is already up when it checks before the tap (#163). False in Release.
    static func skipsSiriAuthorizationPrompt(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        return arguments.contains { LaunchArgument.all.contains($0) }
        #else
        return false
        #endif
    }

    /// How long the read-along controls stay with no interaction, for `-readAlongControlsHideAfter
    /// <seconds>`; `nil` without it or with no number after it (the 3 s then).
    static func readAlongControlsHideAfter(arguments: [String] = ProcessInfo.processInfo.arguments) -> Duration? {
        #if DEBUG
        if let index = arguments.firstIndex(of: LaunchArgument.readAlongControlsHideAfter),
           arguments.indices.contains(index + 1),
           let seconds = Double(arguments[index + 1]), seconds >= 0 {
            return .milliseconds(Int((seconds * 1000).rounded()))
        }
        #endif
        return nil
    }

    /// Reduce Motion forced on, for `-forceReduceMotion`; `nil` follows the system setting.
    static func reduceMotion(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool? {
        #if DEBUG
        if arguments.contains(LaunchArgument.forceReduceMotion) {
            return true
        }
        #endif
        return nil
    }
}
