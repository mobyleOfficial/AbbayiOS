//
//  DataImageView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 26/06/23.
//

import SwiftUI

struct DataImageView: View {
    // MARK: - Properties
    var data: Data?
    var defaultImage: Image = Image(systemName: "photo")

    // MARK: - Body
    var body: some View {
        if let data = data,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
        } else {
            defaultImage
                .resizable()
        }
    }
}

// MARK: - Preview
struct DataImageView_Previews: PreviewProvider {
    static var previews: some View {
        DataImageView()
            .frame(side: SpaceConstants.sx64.value)
    }
}
