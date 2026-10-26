//
//  ExpansionSource.swift
//  Abbay
//

import SwiftUI

/// A cover the player can grow out of (#241): a library cell's, or the Continue card's. Keyed by
/// the book too, so the card showing another book is another source.
struct ExpansionSourceID: Hashable {
    enum Kind: Hashable {
        /// A library grid cell.
        case cell
        /// The library's Continue card.
        case continueCard
    }

    let kind: Kind
    let url: URL?

    static func cell(_ book: AudioModel) -> Self {
        Self(kind: .cell, url: book.url)
    }

    static func continueCard(_ book: AudioModel) -> Self {
        Self(kind: .continueCard, url: book.url)
    }
}

/// Reports the cover's global frame and corner radius to `PlayerPresentation` as it moves, and
/// withdraws it when the cover leaves the hierarchy, so an open from it can grow out of it and
/// the close can land back on it. Writes an unobserved store only: nothing re-renders.
struct ExpansionSourceReporter: ViewModifier {
    let id: ExpansionSourceID
    /// The cover's corner radius; nil follows its size (`ArtworkView.cornerRadius(forSide:)`).
    let cornerRadius: CGFloat?

    @Environment(PlayerPresentation.self)
    private var presentation

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { [presentation, id, cornerRadius] frame in
                let radius = cornerRadius ?? ArtworkView.cornerRadius(forSide: min(frame.width, frame.height))
                presentation.reportSourceCover(ExpansionCover(frame: frame, cornerRadius: radius), for: id)
            }
            .onDisappear { [presentation, id] in
                presentation.removeSourceCover(for: id)
            }
            // Another book in the same place (the Continue card after a switch) is a new source:
            // the old one disappears, and the new one reports its frame at once.
            .id(id)
    }
}

extension View {
    /// Makes this cover one the player can grow out of (`ExpansionSourceReporter`).
    func expansionSource(_ id: ExpansionSourceID, cornerRadius: CGFloat? = nil) -> some View {
        modifier(ExpansionSourceReporter(id: id, cornerRadius: cornerRadius))
    }
}
