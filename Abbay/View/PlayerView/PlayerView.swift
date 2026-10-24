//
//  PlayerView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 10/07/23.
//

import SwiftUI

/// The details screen: cover, title, transport, timeline and the chapter list. It is drawn inside
/// the expansion overlay (`PlayerExpansionOverlay`), which adds the grabber header on top.
///
/// What it reads, so a clock tick does as little as possible:
/// - this body reads the slow state only (the book, playing or not, via `PlayerViewModel`);
/// - `PlayerTimeline` reads `PlaybackClock.bookTime` and re-renders once per tick;
/// - `PlayerChapters` reads `PlaybackClock.currentChapter`, so it re-renders per chapter.
struct PlayerView: View {
    // MARK: - Properties
    /// Shared with the expansion, which draws the growing cover and tint from the same book.
    private let model: PlayerViewModel
    /// The expansion draws the cover itself while it grows from the bar, landing exactly where
    /// this view lays it out; meanwhile the space stays and only the image is hidden.
    @Environment(\.expansionDrawsPlayerCover)
    private var hidesCover
    /// Where the cover is laid out, in `coordinateSpace`: the growing cover's destination.
    private let onCoverFrame: ((CGRect) -> Void)?
    /// Skip amounts and speeds. Changes only from Settings or the speed sheet, never on a tick.
    @Environment(AppSettings.self)
    private var settings
    @State
    private var isShowingSpeed = false

    /// The named space `onCoverFrame` reports in: the details screen's own frame.
    static let coordinateSpace = "player.details"
    static let coverSide: CGFloat = SpaceConstants.sx72.value * SpaceConstants.sx4.value
    static let coverRadius: CGFloat = SpaceConstants.sx32.value

    // MARK: - Inits
    init(model: PlayerViewModel, onCoverFrame: ((CGRect) -> Void)? = nil) {
        self.model = model
        self.onCoverFrame = onCoverFrame
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: SpaceConstants.sx16.value) {
            coverView
            playerView
            PlayerChapters(model: model)
        }
        .padding(.horizontal, SpaceConstants.sx32.value)
        .backgroundColor(ColorConstants.onyx.value)
    }

    // MARK: - Cover view
    private var coverView: some View {
        VStack {
            DataImageView(data: model.book.imageData)
                .scaledToFit()
                .cornerRadius(Self.coverRadius)
                .frame(side: Self.coverSide)
                .opacity(hidesCover ? 0 : 1)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.coordinateSpace))
                } action: { frame in
                    onCoverFrame?(frame)
                }
                .accessibilityHidden(true)
            PlayerTitleView(
                isPlaying: .constant(model.isPlaying),
                text: model.book.title,
                alignment: .center
            )
            .font(.system(size: SpaceConstants.sx24.value))
            .accessibilityIdentifier(AccessibilityID.Player.title)
        }
    }

    // MARK: - Player buttons
    /// Back, play/pause, forward. The skips jump by the Settings amounts, and their SF Symbols
    /// draw that number.
    private var playerButtonsView: some View {
        let back = settings.skipBackward
        let forward = settings.skipForward
        return HStack(spacing: SpaceConstants.sx48.value) {
            IconButtonView(systemName: back.backwardSymbol) {
                model.backward(withSeconds: back.seconds)
            }
            .accessibilityLabel(Localizable.skipBackAction.localized(with: back.rawValue))
            .accessibilityIdentifier(AccessibilityID.Player.transport(AccessibilityID.Transport.back))
            PlayButtonView(isPlaying: .constant(model.isPlaying)) {
                model.play()
            } onPause: {
                model.pause()
            }
            .accessibilityIdentifier(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
            IconButtonView(systemName: forward.forwardSymbol) {
                model.forward(withSeconds: forward.seconds)
            }
            .accessibilityLabel(Localizable.skipForwardAction.localized(with: forward.rawValue))
            .accessibilityIdentifier(AccessibilityID.Player.transport(AccessibilityID.Transport.forward))
        }
        .frame(height: SpaceConstants.sx32.value)
        .foregroundColor(ColorConstants.white.value)
    }

    // MARK: - Player view
    private var playerView: some View {
        VStack(spacing: SpaceConstants.sx16.value) {
            playerButtonsView
            PlayerTimeline(model: model)
            speedButton
        }
    }

    // MARK: - Speed
    private var speedButton: some View {
        let speed = model.speed(in: settings)
        return Button {
            isShowingSpeed = true
        } label: {
            Label(PlaybackSpeed.label(speed), systemImage: "gauge.with.dots.needle.33percent")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, SpaceConstants.sx16.value)
                .padding(.vertical, SpaceConstants.sx8.value)
                .background(ColorConstants.onyx.value, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundColor(speed == PlaybackSpeed.normal ? ColorConstants.white.value : ColorConstants.malachite.value)
        .accessibilityLabel(Localizable.playbackSpeed.localized)
        .accessibilityValue(PlaybackSpeed.label(speed))
        .accessibilityIdentifier(AccessibilityID.Player.speed)
        .sheet(isPresented: $isShowingSpeed) {
            SpeedSheetView(
                speed: model.speed(in: settings),
                defaultSpeed: settings.defaultSpeed,
                onChange: { model.setSpeed($0, in: settings) },
                onSetDefault: { settings.defaultSpeed = $0 }
            )
        }
    }
}

// MARK: - Leaves

/// The timeline and its two timestamps. Reads `PlaybackClock.bookTime` for the loaded book (the
/// book's saved position otherwise), so it is the one part of the screen that ticks.
private struct PlayerTimeline: View {
    let model: PlayerViewModel

    @Environment(PlaybackClock.self)
    private var clock
    /// While the finger scrubs, and after it lifts until the clock reports the seek, the slider
    /// shows the scrubbed time instead of the clock, so it doesn't jump back for a tick.
    @State
    private var scrub = Scrub()

    var body: some View {
        let time = model.bookTime(in: clock)
        PlayerProgressView(
            currentTime: Binding(get: { scrub.time ?? time }, set: { scrub.drag(to: $0) }),
            totalTime: model.book.duration,
            onStartUpdate: { [clock] in
                scrub.drag(to: model.bookTime(in: clock))
            },
            onFinishUpdate: { time in
                model.seek(time)
                scrub.finish()
            }
        )
        .font(.system(size: SpaceConstants.sx16.value))
        .foregroundColor(ColorConstants.white.value)
        .onChange(of: time) {
            scrub.clockMoved()
        }
    }
}

/// The scrubbed time, in a reference type so the slider's touch callbacks (captured once, when its
/// UIKit view is made) always reach the live value. Observable, read only by `PlayerTimeline`.
@MainActor
@Observable
private final class Scrub {
    private(set) var time: Double?
    @ObservationIgnored private var isDragging = false
    @ObservationIgnored private var generation = 0

    func drag(to time: Double) {
        isDragging = true
        if self.time != time { self.time = time }
    }

    /// Keeps the scrubbed time until the clock reports the seek, or 1.5 s if it never does (the
    /// book isn't loaded, or the seek landed on the same second).
    func finish() {
        isDragging = false
        generation += 1
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, generation == current, !isDragging else { return }
            clear()
        }
    }

    func clockMoved() {
        guard !isDragging else { return }
        clear()
    }

    private func clear() {
        if time != nil { time = nil }
    }
}

/// The chapter list. Reads `PlaybackClock.currentChapter` only, so it re-renders when the chapter
/// changes, not on every tick.
private struct PlayerChapters: View {
    let model: PlayerViewModel

    @Environment(PlaybackClock.self)
    private var clock
    @Environment(\.expansionListCollapse)
    private var listCollapse

    var body: some View {
        ChapterListView(
            chapters: model.book.chapters.map(ChapterListView.Item.init),
            currentIndex: model.currentChapter(in: clock),
            downloadState: model.downloadEntry?.state,
            isDimmed: !model.isPlaying,
            layout: .list,
            titleIdentifier: AccessibilityID.Player.chaptersTitle,
            progressIdentifier: AccessibilityID.Player.downloadProgress,
            rowIdentifier: AccessibilityID.Player.chapter,
            onSelect: { model.selectChapter($0) },
            retry: (AccessibilityID.Player.chapterRetry, { model.retryChapter($0) }),
            listCollapse: listCollapse
        )
    }
}

// MARK: - Preview
struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView(model: PlayerViewModel(
            AudioModel(
                title: "title",
                albumName: "album name",
                artist: "",
                duration: 48_657,
                chapters: [ChapterModel].init(
                    repeating: ChapterModel(title: "Chapter"),
                    count: 3
                )
            ),
            state: PlaybackState(),
            player: nil,
            downloads: nil
        ))
        .environment(PlaybackClock())
        .environment(AppSettings(store: InMemoryKeyValueStore()))
    }
}
