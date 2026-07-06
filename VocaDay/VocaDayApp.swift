//
//  VocaDayApp.swift
//  VocaDay
//
//  Created by Jaehyun on 7/6/26.
//

import SwiftUI
import SwiftData

@main
struct VocaDayApp: App {
    private static let cloudKitContainerIdentifier = "iCloud.com.VocaDay.VocaDay"

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            VocabularyDay.self,
            VocaWord.self,
            LCDictationDay.self,
            LCDictationNote.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
