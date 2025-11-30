//
//  LoadAudioUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import CoreData
import Foundation

protocol LoadAudioUseCaseProtocol {
    func execute(url: URL?) -> AudioModel?
}

final class LoadAudioUseCase: LoadAudioUseCaseProtocol {
    func execute(url: URL?) -> AudioModel? {
        AudioDataModel.load(url)?.model
    }
}
