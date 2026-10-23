//
//  DownloadEvent.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// Something that happened to a download, identified by the id it was started with.
public enum DownloadEvent: Equatable {
    /// Bytes written so far. `expectedBytes` is `nil` when the server sent no length.
    case progress(id: String, receivedBytes: Int64, expectedBytes: Int64?)
    /// `location` is a file the provider moved out of URLSession's temp area; the consumer must move it.
    case finished(id: String, location: URL)
    /// The download stopped. Pausing and cancelling both report `.cancelledRequest`.
    case failed(id: String, error: NetworkError)
}
