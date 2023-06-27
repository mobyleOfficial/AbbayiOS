//
//  IconButton.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 26/06/23.
//

import SwiftUI

struct IconButtonView: View {
    // MARK: - Properties
    let systemName: String
    var onTap: VoidCallback?

    // MARK: - Body
    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .onTapGesture {
                onTap?()
            }
    }
}

// MARK: - Preview
struct IconButton_Previews: PreviewProvider {
    static var previews: some View {
        IconButtonView(systemName: "play.fill") {
            print("tap play")
        }
    }
}
