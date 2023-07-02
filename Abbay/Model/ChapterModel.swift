//
//  ChapterModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 02/07/23.
//

struct ChapterModel: Codable {
    var title = String()
    var startTime: Double = .zero
    var duration: Double = .zero

    var endTime: Double {
        startTime + duration
    }
}
