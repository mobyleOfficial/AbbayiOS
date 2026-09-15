//
//  MockUseCases.swift
//  AbbayTests
//

@testable import Abbay
import Foundation

final class MockLoadAudioUseCase: LoadAudioUseCaseProtocol {
    /// Map of url.absoluteString → AudioModel (or absent → nil)
    var stubs: [String: AudioModel] = [:]
    var executeCalls: [URL?] = []

    func execute(url: URL?) -> AudioModel? {
        executeCalls.append(url)
        guard let key = url?.absoluteString else { return nil }
        return stubs[key]
    }
}

final class MockLoadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol {
    var stub: [AudioModel] = []
    var executeCallCount = 0

    func execute() -> [AudioModel] {
        executeCallCount += 1
        return stub
    }
}
