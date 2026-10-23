//
//  LoadAllAudiosUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import Foundation

final class LoadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol {
    private let repository: LoadAllAudiosRepositoryProtocol

    init(repository: LoadAllAudiosRepositoryProtocol = LoadAllAudiosRepository()) {
        self.repository = repository
    }

    func execute() -> [AudioModel] {
        // Mapping faults the chapters relationship, so it runs on the context's queue too.
        LocalStorage.persistent.performAndWait { _ in
            let dataModel = repository.execute() ?? []
            return dataModel.compactMap { $0.model }
        }
    }
}
