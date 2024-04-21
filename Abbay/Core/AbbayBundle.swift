//
//  AbbayBundle.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/04/24.
//

import Foundation

final class AbbayBundle {
    static var value: Bundle {
        Bundle(for: Self.self)
    }
}
