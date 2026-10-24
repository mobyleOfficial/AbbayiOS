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
        Color(uiColor: uiColor)
    }

    /// For UIKit and Core Graphics work, e.g. the cover tint's fallback.
    var uiColor: UIColor {
        let hexCode: String = getBaseValue()
        return UIColor(hex: hexCode)
    }
}
