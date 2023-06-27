//
//  ChapterCountView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import SwiftUI

struct ChapterCountView: View {
    // MARK: - Properties
    @Binding
    var chapter: Int
    var total: Int

    // MARK: - Body
    var body: some View {
        HStack {
            Image(systemName: "book.closed")
            Text("\(chapter)/\(total)")
        }
    }
}

// MARK: - Preview
struct ChapterCountView_Previews: PreviewProvider {
    static var previews: some View {
        ChapterCountView(chapter: .constant(0), total: 13)
    }
}
