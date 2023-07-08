//
//  BinaryFloatingPoint+Extensions.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 19/06/23.
//

infix operator ~/

extension BinaryFloatingPoint {
    static func ~/ (lhs: Self, rhs: Self) -> Int {
        Int(lhs) / Int(rhs)
    }

    static func % (lhs: Self, rhs: Self) -> Self {
        lhs.truncatingRemainder(dividingBy: rhs)
    }

    var timestamp: String {
        let hours = self ~/ 3600
        let minutes = (self % 3600) ~/ 60
        let seconds = Int((self % 3600) % 60)
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
