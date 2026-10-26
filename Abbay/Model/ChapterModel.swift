//
//  ChapterModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 02/07/23.
//

import Foundation

struct ChapterModel: Codable {
    var title = String()
    var startTime: Double = .zero
    var duration: Double = .zero
    var remoteURL: URL?
    var expectedBytes: Int64 = 0

    var endTime: Double {
        startTime + duration
    }
}
