//
//  ChapterDownloadStatusView.swift
//  Abbay
//

import SwiftUI

/// The trailing per-chapter download status: a check, a percentage, or "waiting".
struct ChapterDownloadStatusView: View {
    let state: ChapterDownloadState

    var body: some View {
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
        }
    }
}
