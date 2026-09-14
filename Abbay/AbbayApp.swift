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
    lazy var siriLibraryPublisher: SiriLibraryPublisherProtocol = SiriLibraryPublisher.shared
    lazy var playMediaHandler = InAppPlayMediaHandler()

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

        // Request Siri authorization for the INPlayMediaIntent extension. Without
        // an explicit grant, iOS denies dispatch to the extension at runtime and
        // Siri responds "Abbay hasn't added support for that with Siri".
        // First call surfaces the system permission prompt; subsequent calls are
        // no-ops if status is already determined.
        INPreferences.requestSiriAuthorization { status in
            SiriDiagnostics.record("app launch siriAuth=\(status.rawValue)")
        }

        // Publish the library to Siri on every launch. Apple requires at least one
        // successful entity fetch before entity-parameter phrases ("Play <title> in
        // Abbay") resolve at all, and the snapshot seeder only writes when the
        // snapshot is missing — so launch cannot rely on the write path running.
        siriLibraryPublisher.publish(audios: DependencyContainer.shared.loadAllAudios.execute())

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

    /// Hand the system a real SiriKit handler so it runs resolve, confirm and
    /// handle. Returning nil here leaves it with the bare `handle` hook below,
    /// which makes Siri speak a generic error even when playback succeeds.
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        guard intent is INPlayMediaIntent else { return nil }
        return playMediaHandler
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
