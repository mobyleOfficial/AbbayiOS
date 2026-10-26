//
//  PlayerSiriSignals.swift
//  Abbay
//

import Foundation

/// The player's Siri signals beyond play start (#127): a pause, or an interruption that stops
/// playback (#160), donates the book and asks for a throttled context refresh, and a playing tick
/// that lands in another chapter donates again.
/// Repeats inside a short window are `IntentDonor`'s to drop, the throttle `SiriContextRefresher`'s.
final class PlayerSiriSignals {
    private let donor: IntentDonorProtocol
    private let context: SiriContextRefreshing
    /// The book and chapter of the last playing tick. A tick for another book only records, so
    /// a book's first tick after loading (play start already donated) is not a boundary.
    private var lastChapter: (url: URL?, index: Int)?

    init(donor: IntentDonorProtocol, context: SiriContextRefreshing) {
        self.donor = donor
        self.context = context
    }

    func paused(_ model: AudioModel?) {
        stopped(model, reason: .pause)
    }

    /// An interruption began. Only one that stopped playback counts: a paused player already sent
    /// its signals on `pause()`.
    func interrupted(_ model: AudioModel?, wasPlaying: Bool) {
        guard wasPlaying, model != nil else { return }
        stopped(model, reason: .interruption)
    }

    private func stopped(_ model: AudioModel?, reason: SiriRefreshReason) {
        if let model { donor.donatePlayMedia(model: model) }
        context.refreshIfDue(reason)
    }

    func tick(_ model: AudioModel?, bookTime: Double, isPlaying: Bool) {
        guard isPlaying, let model, let index = model.currentChapter(for: bookTime) else { return }
        defer { lastChapter = (model.url, index) }
        guard let lastChapter, lastChapter.url == model.url, lastChapter.index != index else { return }
        donor.donatePlayMedia(model: model)
    }
}
