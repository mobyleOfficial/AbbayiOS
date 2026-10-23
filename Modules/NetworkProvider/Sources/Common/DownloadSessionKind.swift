//
//  DownloadSessionKind.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// The kind of `URLSession` a `DownloadProvider` runs its downloads on.
public enum DownloadSessionKind {
    /// An in-process session. Downloads stop with the app. Meant for tests and short-lived use.
    case foreground(URLSessionConfiguration = .default)
    /// A system-managed session that keeps downloading while the app is suspended or not running.
    /// Use one identifier per app, and create the provider again at launch to re-attach to its tasks.
    case background(identifier: String)
}
