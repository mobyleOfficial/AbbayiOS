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

    // MARK: - States
    @State
    private var customId = UUID()
    @State
    private var offset: CGFloat = 0
    @State
    private var height: CGFloat = 0

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
        }
        .clipped()
        .frame(height: height)
        .fixedSize(horizontal: false, vertical: true)
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
                height = textGeometry.size.height
                withAnimation(
                    Animation.linear(
                        duration: animationDuration
                    ).delay(startDelay)
                ) {
                    startAnimation(
                        with: textGeometry.size.width < viewGeometry.size.width ? 0
                        : viewGeometry.size.width - textGeometry.size.width
                    )
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
struct SlidingTextView_Previews: PreviewProvider {
    static var previews: some View {
        SlidingTextView(
            text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec cursus sagittis risus quis bibendum."
        )
        .padding(SpaceConstants.sx8.value)
    }
}
