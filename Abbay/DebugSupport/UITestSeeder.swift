//
//  UITestSeeder.swift
//  Abbay
//

#if DEBUG
import Foundation
import UIKit

/// Debug-only library seeding, driven by launch arguments.
///
/// UI tests run the app in a separate process, so there is no initialiser to inject state
/// through -- `XCUIApplication.launchArguments` is the only channel. Wrapped in `#if DEBUG` so
/// the hook cannot reach a Release build.
///
/// The seeded books play real audio (#147): each is a hard link, under its own name, to the
/// public-domain `Christmastide.m4b` fixture that Debug builds carry (Release excludes it, and this
/// file). Rows are keyed by URL, so every book needs its own path; a link stores the 6.5 MB once.
/// Their titles, durations and chapters are the seed's own, not the file's: only *Seeded Playable
/// Book* matches the file. No file behind: `-seedMissingFile`'s book (the moved-file banner) and
/// `-seedTimeLeftEdges`' two, whose clocks must stay where they were saved.
enum UITestSeeder {
    static func run(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        loadAll: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(),
        save: SaveAudioUseCaseProtocol = SaveAudioUseCase(),
        delete: DeleteAudioUseCaseProtocol = DeleteAudioUseCase(),
        audio: (String) -> URL = UITestSeeder.liveAudio()
    ) {
        let wantsSeed = arguments.contains(LaunchArgument.seedLibrary)
        let wantsReset = arguments.contains(LaunchArgument.resetLibrary)
        guard wantsSeed || wantsReset else { return }

        // Always start from empty, so repeated runs are deterministic rather than cumulative.
        delete.execute(loadAll.execute())

        guard wantsSeed else { return }
        var models = seedModels(audio: audio)
        if arguments.contains(LaunchArgument.seedFillerBooks) {
            models += fillerModels(audio: audio)
        }
        if arguments.contains(LaunchArgument.seedLongBook) {
            models.append(longBookModel(audio: audio))
        }
        if arguments.contains(LaunchArgument.seedMissingFile) {
            models.append(missingFileModel())
        }
        if arguments.contains(LaunchArgument.seedTimeLeftEdges) {
            models += timeLeftEdgeModels()
        }
        if arguments.contains(LaunchArgument.seedPlayableBook), let playable = playableBookModel() {
            models.append(playable)
        }
        if arguments.contains(LaunchArgument.seedCoverArt) {
            models = models.map(withCoverArt)
        }
        try? save.execute(models)
    }

    // MARK: - Cover art

    /// The books `-seedCoverArt` gives a cover to.
    static let coverArtTitles: Set<String> = ["Seeded Chaptered Book", playableBookTitle]

    static func withCoverArt(_ book: AudioModel) -> AudioModel {
        guard coverArtTitles.contains(book.title) else { return book }
        var book = book
        book.imageData = coverArt()
        return book
    }

    /// A 300 pt square, warm brown to orange, like the mockups' first cover.
    static func coverArt() -> Data? {
        let side: CGFloat = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { context in
            let colors = [
                UIColor(red: 0.48, green: 0.23, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.82, green: 0.55, blue: 0.31, alpha: 1).cgColor
            ] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)
            else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: side, y: side),
                options: []
            )
        }
        return image.pngData()
    }

    // MARK: - Audio

    /// A URL with no file behind it: what the seeds use when the fixture isn't available.
    static func placeholderAudio(_ name: String) -> URL {
        URL(fileURLWithPath: "/seed/\(name)")
    }

    /// The app's own seed audio: the bundled fixture, linked into Application Support.
    static func liveAudio(fileManager: FileManager = .default) -> (String) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let directory = support?.appendingPathComponent("UITestSeedAudio", isDirectory: true) else {
            return placeholderAudio
        }
        let fixture = Bundle.main.url(forResource: "Christmastide", withExtension: "m4b")
        return linkedFixture(in: directory, fixture: fixture, fileManager: fileManager)
    }

    /// Gives each name a file in `directory` with the fixture's audio: a hard link (a copy if the
    /// link fails), made once and reused. Falls back to `placeholderAudio` without a fixture, or
    /// when the file can't be made.
    static func linkedFixture(
        in directory: URL,
        fixture: URL?,
        fileManager: FileManager = .default
    ) -> (String) -> URL {
        guard let fixture else { return placeholderAudio }
        return { name in
            let url = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { return url }
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                do {
                    try fileManager.linkItem(at: fixture, to: url)
                } catch {
                    try fileManager.copyItem(at: fixture, to: url)
                }
                return url
            } catch {
                return placeholderAudio(name)
            }
        }
    }

    static let missingFileBookTitle = "Seeded Missing Book"

    /// The fixture's length (`Christmastide.m4b`), in seconds.
    static let fixtureDuration = 831.623

    /// A book whose file isn't there, as after a move or rename in Files: Play shows the banner.
    /// Its duration is the fixture's, so the file `-stubMovedImport` imports is recognisably this
    /// book's, moved: the same name and length (#196).
    static func missingFileModel() -> AudioModel {
        AudioModel(
            title: missingFileBookTitle,
            albumName: "Seed Album",
            artist: "Seed Author",
            duration: fixtureDuration,
            url: placeholderAudio("missing.m4b")
        )
    }

    /// *Seeded Missing Book*'s file where it "moved" to, for `-stubMovedImport`: a copy of the
    /// fixture under the book's file name, in `UITestSeedAudio/moved/`. A copy, not a link: the
    /// other seeds are links to the fixture, and one file under two names is one book (#196).
    static func movedMissingFile(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let directory = support?.appendingPathComponent("UITestSeedAudio/moved", isDirectory: true),
              let fixture = Bundle.main.url(forResource: "Christmastide", withExtension: "m4b") else {
            return placeholderAudio("moved/missing.m4b")
        }
        let url = directory.appendingPathComponent("missing.m4b")
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.copyItem(at: fixture, to: url)
        }
        return url
    }

    /// Plain books that only make the list scroll.
    static func fillerModels(count: Int = 12, audio: (String) -> URL = placeholderAudio) -> [AudioModel] {
        (1...count).map { number in
            AudioModel(
                title: "Filler Book \(number)",
                albumName: "Seed Album",
                artist: "Seed Author",
                duration: 100,
                url: audio("filler-\(number).m4b")
            )
        }
    }

    static let longBookTitle = "Seeded Long Book"

    /// One book of 60 one-minute chapters: a chapter list far longer than the screen. The audio is
    /// the 14-minute fixture, so a chapter past the 13th starts past the end of the file.
    static func longBookModel(chapterCount: Int = 60, audio: (String) -> URL = placeholderAudio) -> AudioModel {
        let chapters = (0..<chapterCount).map { index in
            ChapterModel(title: "Long Chapter \(index + 1)", startTime: Double(index) * 60, duration: 60)
        }
        return AudioModel(
            title: longBookTitle,
            albumName: "Seed Album",
            artist: "Seed Author",
            duration: Double(chapterCount) * 60,
            chapters: chapters,
            url: audio("long.m4b")
        )
    }

    static let finishedBookTitle = "Seeded Finished Book"
    static let hourBookTitle = "Seeded Hour Book"

    /// The time-left edge cases (#152): a book without chapters listened to the end (nothing
    /// left), and a book whose first chapter is exactly one hour, which the mini player shows from
    /// 0 s once the book is loaded. No audio on purpose (#147 left them so): playing would move the
    /// clock off the edge being checked.
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

    /// The one seeded book whose chapters are the file's own: `Christmastide.m4b` (public domain, see
    /// `AbbayTests/Fixtures/README.md`), copied into Debug builds only. Its four real chapters,
    /// 200 s in: 56 s into the second, so *Restart chapter* and *Next chapter* both move it.
    /// `nil` if the file isn't in the bundle.
    static func playableBookModel(bundle: Bundle = .main) -> AudioModel? {
        guard let url = bundle.url(forResource: "Christmastide", withExtension: "m4b") else { return nil }
        let starts = [0, 144.015, 288.012, 511.021]
        let duration = fixtureDuration
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
    static func seedModels(audio: (String) -> URL = placeholderAudio) -> [AudioModel] {
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
                url: audio("chaptered.m4b")
            ),
            AudioModel(
                title: "Seeded Plain Book",
                albumName: "Seed Album",
                artist: "Seed Author",
                duration: 200,
                chapters: [],
                url: audio("plain.m4b")
            )
        ]
    }
}
#endif
