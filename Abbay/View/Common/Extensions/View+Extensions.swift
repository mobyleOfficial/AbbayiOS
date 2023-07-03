//
//  View+Extensions.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/06/23.
//

import SwiftUI

extension View {
    @inlinable
    func frame(side: CGFloat, alignment: Alignment = .center) -> some View {
        frame(width: side, height: side, alignment: alignment)
    }

    @inlinable
    func backgroundColor(_ color: Color, ignoresSafeArea: Bool = true) -> some View {
        self.background {
            if ignoresSafeArea {
                color.ignoresSafeArea()
            } else {
                color
            }
        }
    }

    func onTouch(
        limitToBounds: Bool = true,
        onTouchesBegan: OnTouchCallback? = nil,
        onTouchesMoved: OnTouchCallback? = nil,
        onTouchesEnded: OnTouchCallback? = nil,
        onTouchesCancelled: OnTouchCallback? = nil
    ) -> some View {
        modifier(
            OnTouchViewModifier(limitToBounds: limitToBounds) { point in
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
