//
//  InitializableView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 26/06/23.
//

import SwiftUI

struct InitializableView<T>: View where T: View {
    // MARK: - Properties
    @ViewBuilder
    let child: T
    let didInitCallback: VoidCallback

    // MARK: - States
    @State
    private var didInit = false

    // MARK: - Body
    var body: some View {
        child
            .onAppear {
                if !didInit {
                    didInit.toggle()
                    didInitCallback()
                }
            }
    }
}

// MARK: - Preview
struct InitializableView_Previews: PreviewProvider {
    static var previews: some View {
        InitializableView {
            Text("InitializableView")
        } didInitCallback: {}
    }
}
