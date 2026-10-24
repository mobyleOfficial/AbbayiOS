//
//  UITestSeeder.swift
//  Abbay
//

#if DEBUG
import Foundation

/// Debug-only library seeding, driven by launch arguments.
///
/// UI tests run the app in a separate process, so there is no initialiser to inject state
/// through -- `XCUIApplication.launchArguments` is the only channel. Wrapped in `#if DEBUG` so
/// the hook cannot reach a Release build.
///
/// The seeded models deliberately carry no playable audio. They exist so a driver can reach the
/// library row and the player screen and assert their accessibility identifiers. Pressing play
/// still loads the book (the player announces it before any audio is read), so the mini player
/// appears; anything that needs audio to advance still needs a real file.
enum UITestSeeder {
    static func run(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        loadAll: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(),
        save: SaveAudioUseCaseProtocol = SaveAudioUseCase(),
        delete: DeleteAudioUseCaseProtocol = DeleteAudioUseCase()
    ) {
        let wantsSeed = arguments.contains(LaunchArgument.seedLibrary)
        let wantsReset = arguments.contains(LaunchArgument.resetLibrary)
        guard wantsSeed || wantsReset else { return }

        // Always start from empty, so repeated runs are deterministic rather than cumulative.
        for audio in loadAll.execute() {
            delete.execute(audio)
        }

        guard wantsSeed else { return }
        var models = seedModels()
        if arguments.contains(LaunchArgument.seedFillerBooks) {
            models += fillerModels()
        }
        for model in models {
            try? save.execute(model)
        }
    }

    /// Plain books that only make the list scroll.
    static func fillerModels(count: Int = 12) -> [AudioModel] {
        (1...count).map { number in
            AudioModel(
                title: "Filler Book \(number)",
                albumName: "Seed Album",
                artist: "Seed Author",
                duration: 100,
                url: URL(string: "file:///seed/filler-\(number).mp3")
            )
        }
    }

    /// Two books: one chaptered, one without chapters, so both row states are reachable.
    static func seedModels() -> [AudioModel] {
        [
            AudioModel(
                title: "Seeded Chaptered Book",
                albumName: "Seed Album",
                artist: "Seed Author",
                duration: 400,
                chapters: [
                    ChapterModel(title: "Chapter One", startTime: 0, duration: 100),
                    ChapterModel(title: "Chapter Two", startTime: 100, duration: 100),
                    ChapterModel(title: "Chapter Three", startTime: 200, duration: 200)
                ],
                url: URL(string: "file:///seed/chaptered.m4b")
            ),
            AudioModel(
                title: "Seeded Plain Book",
                albumName: "Seed Album",
                artist: "Seed Author",
                duration: 200,
                chapters: [],
                url: URL(string: "file:///seed/plain.mp3")
            )
        ]
    }
}
#endif
