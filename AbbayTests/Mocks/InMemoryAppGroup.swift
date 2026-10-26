//
//  InMemoryAppGroup.swift
//  AbbayTests
//

@testable import Abbay

/// App Group stores over fresh in-memory stores, so a test never reads or writes the real
/// App Group, and needs no clean-up.
extension LastPlayedStore {
    static func inMemory(_ store: KeyValueStoring = InMemoryKeyValueStore()) -> LastPlayedStore {
        LastPlayedStore(store: store, legacyStore: InMemoryKeyValueStore())
    }
}

extension LaunchStateFlag {
    static func inMemory(_ store: KeyValueStoring = InMemoryKeyValueStore()) -> LaunchStateFlag {
        LaunchStateFlag(store: store)
    }
}
