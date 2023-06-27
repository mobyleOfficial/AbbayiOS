//
//  PlayerTitleView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 26/06/23.
//

import SwiftUI

struct PlayerTitleView: View {
    // MARK: - Properties
    @Binding
    var isPlaying: Bool
    let text: String

    // MARK: - Body
    var body: some View {
        SlidingTextView(text: text)
        .foregroundColor(
            isPlaying ? ColorConstants.malachite.value : ColorConstants.white.value
        )
    }
}

// MARK: - Preview
struct PlayerTitleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: SpaceConstants.sx8.value) {
            PlayerTitleView(
                isPlaying: .constant(true),
                text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
            )
            PlayerTitleView(
                isPlaying: .constant(false),
                text: "Text"
            )
        }
        .font(.system(size: SpaceConstants.sx24.value))
        .padding(.bottom, SpaceConstants.sx8.value)
        .preferredColorScheme(.dark)
    }
}
