//
//  AudioModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 19/06/23.
//

import Foundation

struct AudioModel {
    var title = String()
    var albumName = String()
    var artist = String()
    var duration: Double = .zero
    var imageData: Data?
    var chapters = [String]()
    var url: URL?
}
