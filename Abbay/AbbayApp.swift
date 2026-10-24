//
//  AbbayApp.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 14/06/23.
//

import AVFoundation
import CarPlay
import Intents
import os
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Injection seams for testing.
    // `lazy var` so default-args (which touch LibrarySnapshotWriter.shared → LoadAllAudiosUseCase → Core Data)
    // do NOT fire at AppDelegate-construction time, only inside `didFinishLaunching` after DI configure.
    lazy var audioSessionActivator: AudioSessionActivatorProtocol = AudioSessionActivator()
    lazy var seeder: AppDelegateSeederProtocol = AppDelegateSeeder()
    lazy var intentRouter: IntentRouterProtocol = IntentRouter()
    lazy var librarySnapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared
    lazy var playMediaHandler = InAppPlayMediaHandler()
    lazy var launchState: LaunchStateFlag = .shared
    lazy var siriContext: SiriContextRefreshing = DependencyContainer.shared.siriContext
    lazy var backgroundRefresh = SiriBackgroundRefresh(refresher: siriContext)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Pinned order: DI configure → audio session → flag clear + eager seeds (on success)
        DependencyContainer.configure()

        // Launch-argument library seeding for UI tests. Must run before anything reads the
        // library (the snapshot publish below, and MediaListViewModel's init). A no-op in Release.
        DebugOverrides.runLaunchSeeding()

        // Re-attach to the download tasks the system kept running, and restart the missing
        // chapters. After seeding, so it sees the library the rest of the launch sees.
        DependencyContainer.shared.downloads.restore()

        do {
            try audioSessionActivator.activate()
            launchState.clear()
            seeder.seedIfNeeded()
        } catch {
            // No notice at launch: Play reports `audioUnavailable`, and Settings shows the status.
            let error = error as NSError
            Log.player.error(
                "launch: audio session activation failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)"
            )
            launchState.markUnavailable()
        }

        // Request Siri authorization for the INPlayMediaIntent extension. Without
        // an explicit grant, iOS denies dispatch to the extension at runtime and
        // Siri responds "Abbay hasn't added support for that with Siri".
        // First call surfaces the system permission prompt; subsequent calls are
        // no-ops if status is already determined.
        INPreferences.requestSiriAuthorization { status in
            SiriDiagnostics.record("app launch siriAuth=\(status.rawValue)")
        }

        // Rewrite the snapshot, which publishes the library to Siri, on every launch.
        // Apple requires at least one successful entity fetch before entity-parameter
        // phrases ("Play <title> in Abbay") resolve at all, and the snapshot seeder
        // only writes when the snapshot is missing — so launch cannot rely on a
        // mutation having run. The library list used to do this write (#85).
        librarySnapshotWriter.refresh()
        // That write published to Siri: the scene becoming active next needn't publish again.
        siriContext.markPublished()

        // Before launch ends, or `BGTaskScheduler` refuses it. A background launch for the task
        // runs this whole method too, publish included.
        backgroundRefresh.register()

        return true
    }

    /// Siri's context goes stale while the app isn't used (#127): refresh it, throttled, when the
    /// app comes to the foreground, and queue the daily background refresh when it leaves.
    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            siriContext.refreshIfDue(.foreground)
        case .background:
            backgroundRefresh.schedule()
        default:
            break
        }
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

    /// The system relaunched (or woke) the app to deliver the download session's events.
    /// `didFinishLaunching` already re-created the session through `DependencyContainer`.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BookDownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }
        DependencyContainer.shared.downloads.handleBackgroundEvents(completion: completionHandler)
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
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some Scene {
        WindowGroup {
            // Built in the body, after `didFinishLaunching` configured the container. The root
            // injects the playback and download sources and the player presentation.
            AppRootView()
        }
        .onChange(of: scenePhase) { _, phase in
            appDelegate.scenePhaseChanged(to: phase)
        }
    }
}
