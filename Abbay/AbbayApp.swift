//
//  AbbayApp.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 14/06/23.
//

import AVFoundation
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            fatalError("Could not start player session: \(error)")
        }
        return true
    }
}

@main
struct AbbayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    var body: some Scene {
        WindowGroup {
            MediaListView()
        }
    }
}
