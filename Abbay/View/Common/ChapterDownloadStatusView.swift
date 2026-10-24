//
//  ChapterDownloadStatusView.swift
//  Abbay
//

import SwiftUI

/// The trailing per-chapter download status: a check, a percentage, "waiting", or "failed, retry".
struct ChapterDownloadStatusView: View {
    let state: ChapterDownloadState
    /// Makes a failed status a button, with this identifier, that retries the chapter.
    var retry: (identifier: String, action: () -> Void)?

    var body: some View {
        status
            // One line at its full width: the title beside it scrolls, the status never wraps.
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .downloaded:
            Image(systemName: "checkmark")
                .foregroundColor(ColorConstants.malachite.value)
        case let .downloading(fraction):
            Text("\(Int(fraction * 100))%")
                .font(.caption)
                .foregroundColor(ColorConstants.malachite.value)
        case .waiting:
            Text(Localizable.waiting.localized)
                .font(.caption)
                .foregroundColor(ColorConstants.lightSilver.value)
        case .failed:
            failed
        }
    }

    @ViewBuilder
    private var failed: some View {
        let label = Label(Localizable.chapterDownloadFailed.localized, systemImage: "arrow.clockwise")
            .font(.caption)
            .foregroundColor(ColorConstants.maximumRed.value)
        if let retry {
            // Borderless, so in a `List` only the status retries and the rest of the row keeps its tap.
            Button(action: retry.action) { label }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(retry.identifier)
        } else {
            label
        }
    }
}
