//
//  UIColor+Extensions.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/06/23.
//

import UIKit

extension UIColor {
    convenience init(hex: String) {
        var red, green, blue, alpha: CGFloat

        let hex = hex.replacingOccurrences(of: "#", with: String())
        guard let value = Int(hex, radix: 16) else {
            self.init(white: .zero, alpha: .zero)
            return
        }

        func extract(_ value: Int, with numberOfShifts: Int = 0) -> CGFloat {
            CGFloat(value >> numberOfShifts & 0xFF) / 255
        }

        switch hex.count {
        case 3...4:
            // RGB or RGBA
            let expandedHex = hex.map { "\($0)\($0)" }.joined()
            self.init(hex: expandedHex)
            return
        case 6:
            // RRGGBB
            red = extract(value, with: 16)
            green = extract(value, with: 8)
            blue = extract(value)
            alpha = 1
        case 8:
            // RRGGBBAA
            red = extract(value, with: 24)
            green = extract(value, with: 16)
            blue = extract(value, with: 8)
            alpha = extract(value)
        default:
            self.init(white: .zero, alpha: .zero)
            return
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
