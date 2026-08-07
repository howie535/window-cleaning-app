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
    var body: some Scene {
        WindowGroup {
            CustomerListView()
        }
        .modelContainer(for: Customer.self)
    }
}
