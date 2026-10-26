//
//  ArtworkView.swift
//  Abbay
//

import SwiftUI

/// Every cover in the app (#166 G6): embedded artwork (`data:`) or a remote LibriVox cover
/// (`url:`), filling the frame it's given (scaled to fill, clipped), with rounded corners, a 0.5 pt
/// inner stroke and an optional soft shadow. A book without artwork, or a cover that failed to
/// load, shows the generic tile (`ArtworkPlaceholder`), never the `photo` SF Symbol.
///
/// The caller sizes it, usually square: `.frame(side:)` or `.aspectRatio(1, contentMode: .fit)`.
/// The corner radius follows the drawn size (`cornerRadius(forSide:)`) unless one is passed, e.g.
/// the expansion overlay's animated radius.
///
/// Accessibility: an embedded cover is one image element, so an identifier the caller adds lands
/// on a leaf. A remote cover keeps `AsyncImageView`'s own `cover.loading` / `.loaded` / `.failed`
/// identifiers.
struct ArtworkView: View {
    /// The glyph on the generic tile.
    enum Placeholder {
        /// An imported audio file: headphones.
        case audio
        /// A LibriVox book: a closed book.
        case book

        var systemImage: String {
            switch self {
            case .audio: "headphones"
            case .book: "book.closed"
            }
        }
    }

    private enum Source {
        case data(Data?, Placeholder)
        case url(URL, AsyncImageLoader)
    }

    private let source: Source
    private let fixedRadius: CGFloat?
    private let hasShadow: Bool

    /// Embedded artwork; `nil` or undecodable data shows the generic tile.
    init(data: Data?, cornerRadius: CGFloat? = nil, shadow: Bool = false, placeholder: Placeholder = .audio) {
        source = .data(data, placeholder)
        fixedRadius = cornerRadius
        hasShadow = shadow
    }

    /// A library book's embedded artwork, with the placeholder for its kind (`placeholder(for:)`).
    init(book: AudioModel, cornerRadius: CGFloat? = nil, shadow: Bool = false) {
        self.init(
            data: book.imageData,
            cornerRadius: cornerRadius,
            shadow: shadow,
            placeholder: Self.placeholder(for: book)
        )
    }

    /// A remote cover: shimmers while loading, fades in, and falls back to the book tile.
    init(url: URL, cornerRadius: CGFloat? = nil, shadow: Bool = false, loader: AsyncImageLoader = .shared) {
        source = .url(url, loader)
        fixedRadius = cornerRadius
        hasShadow = shadow
    }

    var body: some View {
        let shape = ArtworkShape(fixedRadius: fixedRadius)
        Color.clear
            .overlay { content }
            .clipShape(shape)
            .overlay {
                shape
                    .strokeBorder(ColorConstants.white.value.opacity(Self.strokeOpacity), lineWidth: Self.strokeWidth)
                    .accessibilityHidden(true)
            }
            .shadow(
                color: .black.opacity(hasShadow ? Self.shadowOpacity : 0),
                radius: hasShadow ? Self.shadowRadius : 0,
                y: hasShadow ? Self.shadowOffset : 0
            )
    }

    @ViewBuilder
    private var content: some View {
        switch source {
        case let .data(data, placeholder):
            Group {
                if let image = Self.image(from: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ArtworkPlaceholder(placeholder)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
        case let .url(url, loader):
            AsyncImageView(url: url, loader: loader)
        }
    }

    // MARK: - Decisions

    static let strokeWidth: CGFloat = 0.5
    static let strokeOpacity: Double = 0.15
    static let shadowOpacity: Double = 0.45
    static let shadowRadius: CGFloat = SpaceConstants.sx16.value
    static let shadowOffset: CGFloat = SpaceConstants.sx8.value

    /// The corner radius for a cover drawn `side` points wide: small covers (rows, the mini
    /// player) get tight corners, the player's large cover the ~14 pt of the mockups.
    static func cornerRadius(forSide side: CGFloat) -> CGFloat {
        switch side {
        case ..<40: SpaceConstants.sx4.value
        case ..<120: SpaceConstants.sx8.value
        case ..<200: SpaceConstants.sx12.value
        default: 14
        }
    }

    /// A LibriVox book's tile is a book; an imported file's is headphones.
    static func placeholder(for book: AudioModel) -> Placeholder {
        book.isLibriVox ? .book : .audio
    }

    /// The decoded artwork, or `nil` for the generic tile.
    ///
    /// Decoded once per distinct cover and kept, prepared for display: `body` calls this on every
    /// render, and the player's expansion re-renders the growing cover on every animation frame,
    /// so decoding here each time stuttered the transition on a device (#254).
    static func image(from data: Data?) -> UIImage? {
        guard let data else { return nil }
        let key = data as NSData
        if let cached = decoded.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        let prepared = image.preparingForDisplay() ?? image
        decoded.setObject(prepared, forKey: key, cost: Self.cost(of: prepared))
        return prepared
    }

    /// Decoded covers, keyed by their bytes (an `NSData` key compares by content). Bounded by
    /// decoded size; `NSCache` is thread-safe and empties itself under memory pressure.
    static let decoded: NSCache<NSData, UIImage> = {
        let cache = NSCache<NSData, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// Bytes the decoded bitmap occupies (4 per pixel).
    private static func cost(of image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels) * 4
    }
}

/// The generic cover for a book without artwork, or a cover that failed to load: a dark gradient
/// with a centred glyph, sized to the tile.
struct ArtworkPlaceholder: View {
    let placeholder: ArtworkView.Placeholder

    init(_ placeholder: ArtworkView.Placeholder) {
        self.placeholder = placeholder
    }

    var body: some View {
        LinearGradient(
            colors: [ColorConstants.onyx.value, ColorConstants.background2.value],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            GeometryReader { proxy in
                Image(systemName: placeholder.systemImage)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.light)
                    .foregroundStyle(ColorConstants.spanishGray.value)
                    .frame(side: min(proxy.size.width, proxy.size.height) * Self.glyphFraction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// The glyph's side as a fraction of the tile's.
    static let glyphFraction: CGFloat = 0.4
}

/// A cover's outline: a continuous rounded rectangle whose radius follows its size
/// (`ArtworkView.cornerRadius(forSide:)`), or a fixed radius.
struct ArtworkShape: InsettableShape {
    var fixedRadius: CGFloat?
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: inset, dy: inset)
        let radius = fixedRadius ?? ArtworkView.cornerRadius(forSide: min(rect.width, rect.height))
        return RoundedRectangle(cornerRadius: max(radius - inset, 0), style: .continuous).path(in: insetRect)
    }

    func inset(by amount: CGFloat) -> Self {
        var shape = self
        shape.inset += amount
        return shape
    }
}

// MARK: - Preview
struct ArtworkView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: SpaceConstants.sx16.value) {
            ArtworkView(data: nil)
                .frame(side: SpaceConstants.sx48.value)
            ArtworkView(data: nil, placeholder: .book)
                .frame(side: SpaceConstants.sx96.value)
            ArtworkView(url: URL(fileURLWithPath: "/dev/null/cover.jpg"), shadow: true)
                .frame(side: SpaceConstants.sx96.value * 2)
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}
