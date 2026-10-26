//
//  IntentHandler.swift
//  AbbayIntents
//

import Intents

final class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        guard intent is INPlayMediaIntent else { return self }
        return PlayMediaIntentHandler()
    }
}
