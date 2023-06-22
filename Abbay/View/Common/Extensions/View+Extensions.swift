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
    func backgroundColor(_ color: Color) -> some View {
        ZStack {
            ContainerRelativeShape()
                .fill(color)
                .ignoresSafeArea()
            self
        }
    }
}
