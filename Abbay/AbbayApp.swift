//
//  AbbayApp.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 14/06/23.
//

import AVFoundation
import CarPlay
import Intents
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Injection seams for testing.
    // `lazy var` so default-args (which touch LibrarySnapshotWriter.shared → LoadAllAudiosUseCase → Core Data)
    // do NOT fire at AppDelegate-construction time, only inside `didFinishLaunching` after DI configure.
    lazy var audioSessionActivator: AudioSessionActivatorProtocol = AudioSessionActivator()
    lazy var seeder: AppDelegateSeederProtocol = AppDelegateSeeder()
    lazy var intentRouter: IntentRouterProtocol = IntentRouter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Pinned order: DI configure → audio session → flag clear + eager seeds (on success)
        DependencyContainer.configure()

        do {
            try audioSessionActivator.activate()
            LaunchStateFlag.clear()
            seeder.seedIfNeeded()
        } catch {
            LaunchStateFlag.markUnavailable()
        }

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == UISceneSession.Role.carTemplateApplication {
            let config = UISceneConfiguration(
                name: "CarPlay",
                sessionRole: connectingSceneSession.role
            )
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
    }

    func applicationWillTerminate(_ application: UIApplication) {
        DependencyContainer.shared.player.cleanup()
    }

    func application(
        _ application: UIApplication,
        handle intent: INIntent,
        completionHandler: @escaping (INIntentResponse) -> Void
    ) {
        if let playIntent = intent as? INPlayMediaIntent {
            completionHandler(intentRouter.handle(playIntent))
            return
        }
        // Non-INPlayMediaIntent paths return a generic failure response. Phase-1 AppIntents
        // are dispatched by AppIntents runtime, NOT through this application(_:handle:) hook,
        // so this branch is defensive only.
        completionHandler(INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil))
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
