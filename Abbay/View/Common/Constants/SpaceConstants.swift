//
//  SpaceConstants.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/06/23.
//

import Foundation

enum SpaceConstants: String, CaseIterable {
    case sx2
    case sx4
    case sx8
    case sx12
    case sx16
    case sx20
    case sx24
    case sx28
    case sx32
    case sx36
    case sx40
    case sx44
    case sx48
    case sx52
    case sx56
    case sx60
    case sx64
    case sx68
    case sx72
    case sx76
    case sx80
    case sx84
    case sx88
    case sx92
    case sx96
}

extension SpaceConstants: ConstantsProtocol {
    typealias Value = CGFloat
}
