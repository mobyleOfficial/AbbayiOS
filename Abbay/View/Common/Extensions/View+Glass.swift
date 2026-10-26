//
//  View+Glass.swift
//  Abbay
//

import SwiftUI

// The one place the Liquid Glass redesign (#166) checks the OS. Screens call these helpers and
// never branch on `#available` themselves. On iOS 26 and later they use the real glass APIs; on
// iOS 17–25 they fall back to the plain system look (a material, `.bordered`,
// `.borderedProminent`). The deployment target stays iOS 17.0.
//
// Glass is for controls that float over content (buttons, pills, the chapter panel). Content
// itself (cells, chapter rows on a page) sits on a tinted fill or the background, never on a
// second glass layer.

extension View {
    /// A glass surface behind the view, in `shape`.
    ///
    /// - Parameters:
    ///   - shape: The surface's outline, e.g. `Capsule()` or `RoundedRectangle(cornerRadius: 26)`.
    ///   - tint: Colours the glass (iOS 26) or the material (iOS 17–25).
    ///   - interactive: On iOS 26 the glass reacts to touches, for a control. No effect earlier.
    func abbayGlass(
        in shape: some Shape = Capsule(),
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(AbbayGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    /// A secondary control: `.glass` on iOS 26, `.bordered` earlier.
    func abbayGlassButton() -> some View {
        modifier(AbbayGlassButtonModifier())
    }

    /// The primary control: `.glassProminent` tinted malachite (or `tint`) on iOS 26,
    /// `.borderedProminent` with the same tint earlier.
    func abbayGlassProminentButton(tint: Color = ColorConstants.malachite.value) -> some View {
        modifier(AbbayGlassProminentButtonModifier(tint: tint))
    }

    /// Ties the view's glass to others with the same `id` in an `AbbayGlassContainer`, so iOS 26
    /// morphs between them (a pill growing into a panel). No effect on iOS 17–25, where the
    /// caller's own transition shows instead.
    func abbayGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        modifier(AbbayGlassIDModifier(id: id, namespace: namespace))
    }
}

/// Groups glass views so iOS 26 blends and morphs them together (`GlassEffectContainer`). Earlier
/// it lays out `content` unchanged.
struct AbbayGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder
    let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

/// Whether this OS draws real Liquid Glass. For tests and for copy that has to differ; screens
/// should not branch their layout on it.
enum AbbayGlass {
    static var isAvailable: Bool {
        if #available(iOS 26, *) {
            return true
        }
        return false
    }
}

// MARK: - Modifiers

private struct AbbayGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background {
                    shape
                        .fill(.regularMaterial)
                        .overlay { tint.map { shape.fill($0.opacity(0.25)) } }
                }
                // The thin light edge the mockups give glass, so the fallback still reads as a
                // raised surface on the dark background.
                .overlay { shape.stroke(ColorConstants.white.value.opacity(0.15), lineWidth: 0.5) }
        }
    }
}

private struct AbbayGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct AbbayGlassProminentButtonModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glassProminent).tint(tint)
        } else {
            content.buttonStyle(.borderedProminent).tint(tint)
        }
    }
}

private struct AbbayGlassIDModifier<ID: Hashable & Sendable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}
