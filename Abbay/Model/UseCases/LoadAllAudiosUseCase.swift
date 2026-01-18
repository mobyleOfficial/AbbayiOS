//
//  LoadAllAudiosUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import Foundation

protocol LoadAllAudiosUseCaseProtocol {
    func execute() -> [AudioModel]
}

final class LoadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol {
    private let repository: LoadAllAudiosRepositoryProtocol

    init(repository: LoadAllAudiosRepositoryProtocol) {
        self.repository = repository
    }

    func execute() -> [AudioModel] {
        let dataModel = repository.execute() ?? []
        return dataModel.compactMap { $0.model }
    }
}
