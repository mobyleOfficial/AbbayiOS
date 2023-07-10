//
//  SlidingTextView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 26/06/23.
//

import SwiftUI

struct SlidingTextView: View {
    // MARK: - Properties
    let text: String
    var duration: Double?
    var startDelay: Double = 3
    var endDelay: Double = 3
    var alignment: Alignment = .leading

    // MARK: - States
    @State
    private var customId = UUID()
    @State
    private var offset: CGFloat = .zero
    @State
    private var size: CGSize = .zero

    // MARK: - Computed properties
    private var animationDuration: Double {
        duration ?? Double(text.count) * 0.1
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { viewGeometry in
            Text(text)
                .offset(x: offset)
                .fixedSize()
                .background {
                    GeometryReader { textGeometry in
                        animateText(
                            withViewDimensions: viewGeometry,
                            withTextDimensions: textGeometry
                        )
                    }
                }
                .frame(
                    width: viewGeometry.size.width,
                    alignment: alignment,
                    conditional: size.width <= viewGeometry.size.width
                )
        }
        .clipped()
        .frame(height: size.height)
        .id(customId)
    }

    // MARK: - Helpers
    @ViewBuilder
    func animateText(
        withViewDimensions viewGeometry: GeometryProxy,
        withTextDimensions textGeometry: GeometryProxy
    ) -> some View {
        ZStack {}
            .onAppear {
                size = textGeometry.size
                withAnimation(
                    Animation.linear(
                        duration: animationDuration
                    ).delay(startDelay)
                ) {
                    if textGeometry.size.width > viewGeometry.size.width {
                        startAnimation(
                            with: textGeometry.size.width < viewGeometry.size.width ? 0
                            : viewGeometry.size.width - textGeometry.size.width
                        )
                    }
                }
            }
    }

    func startAnimation(with offset: CGFloat) {
        self.offset = offset
        DispatchQueue.main.asyncAfter(
            deadline: .now() + animationDuration + startDelay + endDelay
        ) {
            self.offset = .zero
            customId = UUID()
        }
    }
}

// MARK: - Preview
// swiftlint:disable line_length
struct SlidingTextView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            SlidingTextView(
                text: "Lorem ipsum dolor sit amet"
            )
            SlidingTextView(
                text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec cursus sagittis risus quis bibendum."
            )
        }
        .padding(SpaceConstants.sx8.value)
    }
}
// swiftlint:enable line_length
