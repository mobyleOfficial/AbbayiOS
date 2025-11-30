//
//  LoadAllAudiosUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import CoreData
import Foundation

protocol LoadAllAudiosUseCaseProtocol {
    func execute() -> [AudioModel]
}

final class LoadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol {
    func execute() -> [AudioModel] {
        AudioDataModel.load()
            .compactMap { $0.model }
            .sorted(by: { $0.title.lowercased() < $1.title.lowercased() })
    }
}
