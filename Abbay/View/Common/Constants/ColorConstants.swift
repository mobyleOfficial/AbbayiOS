//
//  ColorConstants.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/06/23.
//

import SwiftUI

enum ColorConstants: String, CaseIterable {
    case background
    case white
    case maximumRed
    case lightSilver
    case malachite
    case onyx
    case spanishGray
    case background2
    case clear
}

extension ColorConstants: ConstantsProtocol {
    var value: Color {
        let hexCode: String = getBaseValue()
        let uiColor = UIColor(hex: hexCode)
        return Color(uiColor: uiColor)
    }
}
