//
//  TrainingLogWatchApp.swift
//  TrainingLogWatch Watch App
//
//  Created by Dmitry Charsov on 24.09.2026.
//

import SwiftUI
import WatchKit

@main
struct TrainingLogWatch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(HealthRecoveryDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class HealthRecoveryDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() { Task { @MainActor in await WatchHealth.shared.load(); await WatchHealth.shared.recover() } }
}
