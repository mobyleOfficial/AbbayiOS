//
//  SaveAudioUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import CoreData
import Foundation

protocol SaveAudioUseCaseProtocol {
    func execute(_ audio: AudioModel) throws
}

final class SaveAudioUseCase: SaveAudioUseCaseProtocol {
    func execute(_ audio: AudioModel) throws {
        _ = audio.dataModel
        try LocalStorage.persistent.managedContext.save()
    }
}
