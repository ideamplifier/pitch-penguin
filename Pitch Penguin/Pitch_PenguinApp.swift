//
//  Pitch_PenguinApp.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI
import SwiftData

@main
struct Pitch_PenguinApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
