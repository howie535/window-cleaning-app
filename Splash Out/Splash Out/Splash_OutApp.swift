//
//  Splash_OutApp.swift
//  Splash Out
//
//  Created by Howard Fletcher on 07/08/2026.
//

import SwiftUI
import SwiftData

@main
struct Splash_OutApp: App {
    private let container: ModelContainer

    init() {
        container = Persistence.makeContainer()
        SimulatorImport.runIfRequested(container: container)
        Persistence.seedDefaultsIfNeeded(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
