//
//  IconButtonView.swift
//  Abbay
//

import SwiftUI

struct IconButtonView: View {
    let systemName: String
    var onTap: VoidCallback?

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .onTapGesture {
                onTap?()
            }
            // This is an `Image` with a tap gesture rather than a `Button`, so it is not an
            // accessibility element by default and a UI driver could not reach it. Promote it to
            // a single element with the button trait; call sites attach the identifier.
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
    }
}

struct IconButton_Previews: PreviewProvider {
    static var previews: some View {
        IconButtonView(systemName: "play.fill") {
            print("tap play")
        }
    }
}
