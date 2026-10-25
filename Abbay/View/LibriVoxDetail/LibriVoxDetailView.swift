//
//  LibriVoxDetailView.swift
//  Abbay
//

import SwiftUI

struct LibriVoxDetailView: View {
    @StateObject
    private var model: LibriVoxDetailViewModel
    @State
    private var isExpanded = false

    init(
        book: LibriVoxBook,
        onAdded: @escaping (AudioModel) -> Void,
        openPlayer: @escaping (AudioModel) -> Void
    ) {
        _model = StateObject(wrappedValue: LibriVoxDetailViewModel(
            book: book,
            client: Self.makeClient(),
            downloads: DependencyContainer.shared.downloads,
            downloadStates: DependencyContainer.shared.downloadStates,
            saveAudio: SaveAudioUseCase(),
            path: NetworkPathMonitor.shared,
            cellularPreference: { DependencyContainer.shared.settings.cellularPreference },
            onAdded: onAdded,
            openPlayer: openPlayer
        ))
    }

    private static func makeClient() -> LibriVoxClientProtocol {
        DebugOverrides.libriVoxClient() ?? LibriVoxClient()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundColor(ColorConstants.background.value)
            .foregroundColor(ColorConstants.white.value)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(AccessibilityID.Detail.view)
            .task { await model.load() }
            .alert(
                Localizable.largeDownloadTitle.localized,
                isPresented: $model.isShowingCellularAlert
            ) {
                Button(Localizable.continueDownload.localized) { model.confirmCellular(continue: true) }
                    .accessibilityIdentifier(AccessibilityID.Detail.cellularContinue)
                Button(Localizable.waitForWiFi.localized) { model.confirmCellular(continue: false) }
                    .accessibilityIdentifier(AccessibilityID.Detail.cellularWait)
            } message: {
                Text(Localizable.largeDownloadMessage.localized(with: sizeText))
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let details = model.details {
            loaded(details)
        } else if model.loadFailed {
            VStack(spacing: SpaceConstants.sx16.value) {
                Text(Localizable.detailsFailed.localized)
                    .foregroundColor(ColorConstants.lightSilver.value)
                Button(Localizable.retry.localized) {
                    Task { await model.load() }
                }
                .buttonStyle(DetailButtonStyle(isPrimary: false))
                .accessibilityIdentifier(AccessibilityID.Detail.retry)
            }
            .padding(SpaceConstants.sx32.value)
        } else {
            ProgressView()
        }
    }

    private func loaded(_ details: LibriVoxBookDetails) -> some View {
        let book = details.book
        return ScrollView {
            VStack(alignment: .leading, spacing: SpaceConstants.sx16.value) {
                header(book)
                descriptionView(book)
                actionButton
                chapterList(book)
                Text(Localizable.librivoxCredit.localized)
                    .font(.caption)
                    .foregroundColor(ColorConstants.lightSilver.value)
                    .frame(maxWidth: .infinity)
            }
            .padding(SpaceConstants.sx16.value)
        }
    }

    private var sizeText: String {
        ByteSize.text(model.totalBytes)
    }

    private func header(_ book: LibriVoxBook) -> some View {
        HStack(alignment: .top, spacing: SpaceConstants.sx16.value) {
            AsyncImageView(url: book.coverURL)
                .frame(side: SpaceConstants.sx84.value)
                .cornerRadius(SpaceConstants.sx8.value)
            VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
                Text(book.title)
                    .font(.headline)
                Text(book.authors)
                    .foregroundColor(ColorConstants.lightSilver.value)
                Text(summary(book))
                    .font(.caption)
                    .foregroundColor(ColorConstants.lightSilver.value)
                Text(sizeText)
                    .font(.caption)
                    .foregroundColor(ColorConstants.lightSilver.value)
            }
        }
    }

    private func summary(_ book: LibriVoxBook) -> String {
        [
            Self.durationText(book.totalSeconds),
            Localizable.chaptersCount.localized(with: book.sections.count),
            book.languageName
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    /// "2h 58m", or "58m" under an hour.
    static func durationText(_ seconds: Double) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func descriptionView(_ book: LibriVoxBook) -> some View {
        VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
            Text(book.descriptionText)
                .lineLimit(isExpanded ? nil : 3)
                .foregroundColor(ColorConstants.lightSilver.value)
            if !isExpanded && !book.descriptionText.isEmpty {
                Button(Localizable.more.localized) { isExpanded = true }
                    .foregroundColor(ColorConstants.malachite.value)
                    .accessibilityIdentifier(AccessibilityID.Detail.more)
            }
        }
    }

    // MARK: - Download / Play

    @ViewBuilder
    private var actionButton: some View {
        if model.addedBook == nil {
            Button {
                model.downloadTapped()
            } label: {
                Label(Localizable.download.localized, systemImage: "arrow.down")
            }
            .buttonStyle(DetailButtonStyle(isPrimary: true))
            .accessibilityIdentifier(AccessibilityID.Detail.download)
        } else {
            Button {
                model.play()
            } label: {
                Label(Localizable.play.localized, systemImage: "play.fill")
            }
            .buttonStyle(DetailButtonStyle(isPrimary: true))
            .accessibilityIdentifier(AccessibilityID.Detail.play)
        }
    }

    /// The player's chapter list, embedded in this page's scroll view. Rows are not tappable:
    /// Play opens the player, which is where chapters are chosen. A failed chapter's status retries it.
    private func chapterList(_ book: LibriVoxBook) -> some View {
        ChapterListView(
            chapters: book.sections.map(ChapterListView.Item.init),
            downloadState: model.downloadState,
            layout: .stack,
            progressIdentifier: AccessibilityID.Detail.progress,
            isHeldByLowDataMode: model.isHeldByLowDataMode,
            lowDataModeIdentifier: AccessibilityID.Detail.lowDataMode,
            emptyIdentifier: AccessibilityID.Detail.chaptersEmpty,
            rowIdentifier: AccessibilityID.Detail.chapter,
            retry: (AccessibilityID.Detail.chapterRetry, { model.retryChapter($0) })
        )
    }
}

private struct DetailButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(isPrimary ? ColorConstants.background2.value : ColorConstants.white.value)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpaceConstants.sx16.value)
            .background(isPrimary ? ColorConstants.malachite.value : ColorConstants.onyx.value)
            .cornerRadius(SpaceConstants.sx12.value)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
