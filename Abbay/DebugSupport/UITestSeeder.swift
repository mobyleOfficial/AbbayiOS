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
        delete.execute(loadAll.execute())

        guard wantsSeed else { return }
        var models = seedModels()
        if arguments.contains(LaunchArgument.seedFillerBooks) {
            models += fillerModels()
        }
        if arguments.contains(LaunchArgument.seedLongBook) {
            models.append(longBookModel())
        }
        if arguments.contains(LaunchArgument.seedTimeLeftEdges) {
            models += timeLeftEdgeModels()
        }
        if arguments.contains(LaunchArgument.seedPlayableBook), let playable = playableBookModel() {
            models.append(playable)
        }
        try? save.execute(models)
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

    static let longBookTitle = "Seeded Long Book"

    /// One book of 60 one-minute chapters: a chapter list far longer than the screen.
    static func longBookModel(chapterCount: Int = 60) -> AudioModel {
        let chapters = (0..<chapterCount).map { index in
            ChapterModel(title: "Long Chapter \(index + 1)", startTime: Double(index) * 60, duration: 60)
        }
        return AudioModel(
            title: longBookTitle,
            albumName: "Seed Album",
            artist: "Seed Author",
            duration: Double(chapterCount) * 60,
            chapters: chapters,
            url: URL(string: "file:///seed/long.m4b")
        )
    }

    static let finishedBookTitle = "Seeded Finished Book"
    static let hourBookTitle = "Seeded Hour Book"

    /// The time-left edge cases (#152): a book without chapters listened to the end (nothing
    /// left), and a book whose first chapter is exactly one hour, which the mini player shows from
    /// 0 s once the book is loaded.
    static func timeLeftEdgeModels() -> [AudioModel] {
        [
            AudioModel(
                title: finishedBookTitle,
                albumName: "Seed Album",
                artist: "Seed Author",
                duration: 200,
                currentTime: 200,
                chapters: [],
                url: URL(string: "file:///seed/finished.mp3")
            ),
            AudioModel(
                title: hourBookTitle,
                albumName: "Seed Album",
                artist: "Seed Author",
                duration: 5400,
                chapters: [
                    ChapterModel(title: "Hour Chapter", startTime: 0, duration: 3600),
                    ChapterModel(title: "Half Hour Chapter", startTime: 3600, duration: 1800)
                ],
                url: URL(string: "file:///seed/hour.m4b")
            )
        ]
    }

    static let playableBookTitle = "Seeded Playable Book"

    /// The one seeded book with real audio: `Christmastide.m4b` (public domain, see
    /// `AbbayTests/Fixtures/README.md`), copied into Debug builds only. Its four real chapters,
    /// 200 s in: 56 s into the second, so *Restart chapter* and *Next chapter* both move it.
    /// `nil` if the file isn't in the bundle.
    static func playableBookModel(bundle: Bundle = .main) -> AudioModel? {
        guard let url = bundle.url(forResource: "Christmastide", withExtension: "m4b") else { return nil }
        let starts = [0, 144.015, 288.012, 511.021]
        let duration = 831.623
        let chapters = starts.indices.map { index in
            let end = index + 1 < starts.count ? starts[index + 1] : duration
            return ChapterModel(title: "Poem \(index + 1)", startTime: starts[index], duration: end - starts[index])
        }
        return AudioModel(
            title: playableBookTitle,
            albumName: "Christmastide",
            artist: "Various",
            duration: duration,
            currentTime: 200,
            chapters: chapters,
            url: url
        )
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
