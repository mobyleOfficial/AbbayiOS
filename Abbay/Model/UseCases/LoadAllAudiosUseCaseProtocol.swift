//
//  LoadAllAudiosUseCaseProtocol.swift
//  Abbay
//
//  Extracted so the AbbayIntents extension can compile against the
//  protocol without pulling in `LoadAllAudiosRepository` (Core Data).
//

import Foundation

protocol LoadAllAudiosUseCaseProtocol {
    func execute() -> [AudioModel]
}
