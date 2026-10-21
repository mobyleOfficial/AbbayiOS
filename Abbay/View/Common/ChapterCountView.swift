//
//  ChapterCountView.swift
//  Abbay
//

import SwiftUI

struct ChapterCountView: View {
    @Binding
    var chapter: Int
    var total: Int

    /// Chapter indices are 0-based everywhere behind the UI (`AudioModel.currentChapter(for:)`
    /// and every view model), while this counter reads 1-based. The conversion lives here, in
    /// the one place that displays it, rather than in each view model -- doing it per view model
    /// is what produced three different conventions and a row that read "0/3" at rest (#104).
    ///
    /// A book with no chapter metadata reads 0/0, not 1/0. The clamp keeps an out-of-range index
    /// from rendering something impossible like 4/3.
    static func displayNumber(forIndex index: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return min(index + 1, total)
    }

    var body: some View {
        HStack {
            Image(systemName: "book.closed")
            Text(
                Localizable.chapterCount.localized(
                    with: Self.displayNumber(forIndex: chapter, total: total),
                    total
                )
            )
        }
    }
}

struct ChapterCountView_Previews: PreviewProvider {
    static var previews: some View {
        ChapterCountView(chapter: .constant(0), total: 13)
    }
}
