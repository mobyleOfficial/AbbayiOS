//
//  ProgressView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import SwiftUI

struct PlayerProgressView: View {
    // MARK: - Properties
    @Binding
    var currentTime: Double
    var totalTime: Double
    var tint: Color = ColorConstants.malachite.value

    // MARK: - Body
    var body: some View {
        VStack {
            ProgressView(value: currentTime, total: totalTime)
                .tint(tint)
                .progressViewStyle(.linear)
            HStack {
                Text(currentTime.timestamp)
                Spacer()
                Text(totalTime.timestamp)
            }
        }
    }
}

// MARK: - Preview
struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerProgressView(
            currentTime: .constant(1500),
            totalTime: 3000
        )
    }
}
