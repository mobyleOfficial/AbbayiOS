//
//  OnTouchView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 02/07/23.
//

// https://www.hackingwithswift.com/quick-start/swiftui/how-to-detect-the-location-of-a-tap-inside-a-view

import SwiftUI

// MARK: - OnTouchCallback
typealias OnTouchCallback = (CGPoint) -> Void

// MARK: - OnTouchView
struct OnTouchView: UIViewRepresentable {
    var limitToBounds = true
    var onTouchesBegan: OnTouchCallback?
    var onTouchesMoved: OnTouchCallback?
    var onTouchesEnded: OnTouchCallback?
    var onTouchesCancelled: OnTouchCallback?

    // MARK: - UIViewRepresentable
    func makeUIView(context: Context) -> OnTouchUIView {
        let view = OnTouchUIView()
        view.onTouchesBegan = onTouchesBegan
        view.onTouchesMoved = onTouchesMoved
        view.onTouchesEnded = onTouchesEnded
        view.onTouchesCancelled = onTouchesCancelled
        view.limitToBounds = limitToBounds
        return view
    }

    func updateUIView(_ uiView: OnTouchUIView, context: Context) {
        /* Empty */
    }
}

extension OnTouchView {
    // MARK: - OnTouchType
    private enum OnTouchType {
        case began
        case moved
        case ended
        case cancelled
    }

    // MARK: - OnTouchUIView
    final class OnTouchUIView: UIView {
        var limitToBounds = true
        var onTouchesBegan: OnTouchCallback?
        var onTouchesMoved: OnTouchCallback?
        var onTouchesEnded: OnTouchCallback?
        var onTouchesCancelled: OnTouchCallback?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            send(location, forEvent: .began)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            send(location, forEvent: .moved)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            send(location, forEvent: .ended)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            send(location, forEvent: .cancelled)
        }

        private func send(_ location: CGPoint, forEvent event: OnTouchType) {
            if !limitToBounds || bounds.contains(location) {
                switch event {
                case .began:
                    onTouchesBegan?(location)
                case .moved:
                    onTouchesMoved?(location)
                case .ended:
                    onTouchesEnded?(location)
                case .cancelled:
                    onTouchesCancelled?(location)
                }
            }
        }
    }
}

// MARK: - OnTouchViewModifier
struct OnTouchViewModifier: ViewModifier {
    var limitToBounds = true
    var onTouchesBegan: OnTouchCallback?
    var onTouchesMoved: OnTouchCallback?
    var onTouchesEnded: OnTouchCallback?
    var onTouchesCancelled: OnTouchCallback?

    func body(content: Content) -> some View {
        content
            .overlay(
                OnTouchView(limitToBounds: limitToBounds) { point in
                    onTouchesBegan?(point)
                } onTouchesMoved: { point in
                    onTouchesMoved?(point)
                } onTouchesEnded: { point in
                    onTouchesEnded?(point)
                } onTouchesCancelled: { point in
                    onTouchesCancelled?(point)
                }
            )
    }
}
