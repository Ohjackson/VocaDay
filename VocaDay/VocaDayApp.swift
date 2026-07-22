//
//  VocaDayApp.swift
//  VocaDay
//
//  Created by Jaehyun on 7/6/26.
//

import SwiftUI
import SwiftData
#if os(macOS)
import Carbon
#endif

#if os(macOS)
let quickAddRequestedNotification = Notification.Name("vocaDayQuickAddRequested")

private final class GlobalQuickAddShortcut {
    static let shared = GlobalQuickAddShortcut()

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    private init() {}

    func start() {
        guard hotKeyReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotKey,
            1,
            &eventType,
            nil,
            &eventHandlerReference
        )

        let hotKeyID = EventHotKeyID(signature: 0x564F4341, id: 1) // "VOCA"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_J),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
    }

    private static let handleHotKey: EventHandlerUPP = { _, event, _ in
        guard let event else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == 0x564F4341, hotKeyID.id == 1 else {
            return noErr
        }

        NotificationCenter.default.post(name: quickAddRequestedNotification, object: nil)
        return noErr
    }
}
#endif

@main
struct VocaDayApp: App {
    private static let cloudKitContainerIdentifier = "iCloud.com.VocaDay.VocaDay"

    init() {
        #if os(macOS)
        GlobalQuickAddShortcut.shared.start()
        #endif
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            VocabularyDay.self,
            VocaWord.self,
            LCDictationDay.self,
            LCDictationNote.self,
            GrammarNote.self,
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
