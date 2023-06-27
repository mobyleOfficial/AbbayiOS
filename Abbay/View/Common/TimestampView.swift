//
//  TimestampView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import SwiftUI

struct TimestampView: View {
    // MARK: - Properties
    @Binding
    var current: Double
    var total: Double

    // MARK: - Body
    var body: some View {
        HStack {
            Image(systemName: "clock")
            Text("\(current.timestamp)/\(total.timestamp)")
        }
    }
}

// MARK: - Preview
struct TimestampView_Previews: PreviewProvider {
    static var previews: some View {
        TimestampView(current: .constant(0), total: 3000)
    }
}
