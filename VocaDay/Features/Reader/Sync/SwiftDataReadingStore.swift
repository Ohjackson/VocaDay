import CoreData
import Foundation
import Observation
import os
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 계약 2 `ReadingStore`의 앱 구현. 앱 `ModelContainer`(CloudKit private DB)에 쓴다.
///
/// - 화면은 메모리 사본(`positions`, `marksByBook`)을 읽는다. 이 값이 바뀌면 화면이 다시 그려진다.
/// - 읽은 위치는 문장마다 쓰지 않는다. `flushDelay` 동안 모았다가 한 번에 쓰고, 앱이 비활성화될 때도 쓴다.
/// - 다른 기기 변경(`NSPersistentStoreRemoteChange`)이나 앱 활성화 때 저장소를 다시 읽고 중복 위치 행을 정리한다.
@Observable
final class SwiftDataReadingStore: ReadingStore {
    private static let logger = Logger(subsystem: "VocaDay", category: "ReadingStore")
    private static var sharedStores: [ObjectIdentifier: SwiftDataReadingStore] = [:]

    /// 앱 루트에서 쓴다. 같은 컨테이너에는 같은 저장소를 돌려준다 (body가 다시 불려도 새로 만들지 않는다).
    static func shared(in container: ModelContainer) -> SwiftDataReadingStore {
        let key = ObjectIdentifier(container)
        if let store = sharedStores[key] { return store }
        let store = SwiftDataReadingStore(container: container)
        sharedStores[key] = store
        return store
    }

    private var positions: [String: ReadingPosition] = [:]
    private var marksByBook: [String: [ReaderBookmark]] = [:]

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let flushDelay: Duration
    @ObservationIgnored private var positionDates: [String: Date] = [:]
    /// 아직 디스크에 쓰지 않은 위치.
    @ObservationIgnored private var pending: [String: PendingPosition] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private let observers = NotificationObservers()
    @ObservationIgnored private let now: () -> Date

    private struct PendingPosition {
        var position: ReadingPosition
        var updatedAt: Date
    }

    /// - Parameters:
    ///   - flushDelay: 위치 변경을 모으는 시간.
    ///   - observesSystemEvents: 원격 변경·앱 활성 상태 알림을 받을지. 테스트에서는 끈다.
    init(
        container: ModelContainer,
        flushDelay: Duration = .seconds(3),
        observesSystemEvents: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.container = container
        self.flushDelay = flushDelay
        self.now = now
        reload()
        if observesSystemEvents {
            observeSystemEvents()
        }
    }

    // MARK: - ReadingStore

    func lastPosition(bookID: String) -> ReadingPosition? {
        positions[bookID]
    }

    func saveLastPosition(_ position: ReadingPosition, bookID: String) {
        guard positions[bookID] != position else { return }
        let date = now()
        positions[bookID] = position
        positionDates[bookID] = date
        pending[bookID] = PendingPosition(position: position, updatedAt: date)
        scheduleFlush()
    }

    func bookmarks(bookID: String) -> [ReaderBookmark] {
        marksByBook[bookID] ?? []
    }

    @discardableResult
    func addBookmark(at position: ReadingPosition, bookID: String, note: String) -> ReaderBookmark {
        let record = ReaderBookmarkRecord(bookID: bookID, position: position, note: note, createdAt: now())
        let mark = record.bookmark
        let context = makeContext()
        context.insert(record)
        save(context, action: "addBookmark")
        marksByBook[bookID] = ReaderBookmarkMerge.sorted((marksByBook[bookID] ?? []) + [mark])
        return mark
    }

    func removeBookmark(id: UUID) {
        let context = makeContext()
        let descriptor = FetchDescriptor<ReaderBookmarkRecord>(predicate: #Predicate { $0.id == id })
        let rows = (try? context.fetch(descriptor)) ?? []
        rows.forEach(context.delete)
        if !rows.isEmpty {
            save(context, action: "removeBookmark")
        }
        for (bookID, marks) in marksByBook where marks.contains(where: { $0.id == id }) {
            marksByBook[bookID] = marks.filter { $0.id != id }
        }
    }

    // MARK: - 저장소와 맞추기

    /// 모아 둔 위치를 지금 쓴다. 앱이 비활성화될 때도 불린다.
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty else { return }
        let entries = pending
        pending = [:]

        let context = makeContext()
        for (bookID, entry) in entries {
            let descriptor = FetchDescriptor<ReaderPositionRecord>(predicate: #Predicate { $0.bookID == bookID })
            let rows = (try? context.fetch(descriptor)) ?? []
            let (keep, discard) = ReaderPositionMerge.split(rows)
            discard.forEach(context.delete)
            if let row = keep[bookID] {
                if entry.updatedAt >= row.updatedAt {
                    row.position = entry.position
                    row.updatedAt = entry.updatedAt
                } else {
                    // 그사이 다른 기기가 더 늦게 쓴 위치가 들어왔다 → 그 값을 따른다.
                    adoptPosition(row.position, date: row.updatedAt, bookID: bookID)
                }
            } else {
                context.insert(ReaderPositionRecord(bookID: bookID, position: entry.position, updatedAt: entry.updatedAt))
            }
        }
        save(context, action: "flush")
    }

    /// 저장소 전체를 다시 읽는다. 위치 중복 행은 가장 늦은 값만 남기고 지운다.
    /// 아직 쓰지 않은 위치가 저장소 값보다 늦으면 그 값을 유지한다.
    func reload() {
        let context = makeContext()

        let positionRows = (try? context.fetch(FetchDescriptor<ReaderPositionRecord>())) ?? []
        let (keep, discard) = ReaderPositionMerge.split(positionRows)
        discard.forEach(context.delete)

        var newPositions = keep.mapValues(\.position)
        var newDates = keep.mapValues(\.updatedAt)
        for (bookID, entry) in pending {
            if entry.updatedAt >= (newDates[bookID] ?? .distantPast) {
                newPositions[bookID] = entry.position
                newDates[bookID] = entry.updatedAt
            } else {
                pending[bookID] = nil
            }
        }

        let bookmarkRows = (try? context.fetch(FetchDescriptor<ReaderBookmarkRecord>())) ?? []
        let newMarks = Dictionary(grouping: ReaderBookmarkMerge.unique(bookmarkRows), by: \.bookID)

        if !discard.isEmpty {
            save(context, action: "mergeDuplicatePositions")
        }

        positionDates = newDates
        // 같은 값이면 다시 넣지 않는다 (불필요한 다시 그리기 방지).
        if positions != newPositions { positions = newPositions }
        if marksByBook != newMarks { marksByBook = newMarks }
    }

    // MARK: - 내부

    private func adoptPosition(_ position: ReadingPosition, date: Date, bookID: String) {
        positionDates[bookID] = date
        if positions[bookID] != position { positions[bookID] = position }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let delay = flushDelay
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flushTask = nil
            self?.flush()
        }
    }

    /// 원격 변경 알림은 한꺼번에 여러 번 온다 → 잠깐 모아서 한 번 읽는다.
    private func scheduleReload() {
        guard reloadTask == nil else { return }
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reloadTask = nil
            self?.reload()
        }
    }

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func save(_ context: ModelContext, action: String) {
        if let error = context.saveReportingError() {
            Self.logger.error("\(action, privacy: .public) save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        let onRemoteChange: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        let onBecomeActive: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        let onLeave: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }

        observers.add(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main, using: onRemoteChange))
        #if canImport(UIKit)
        observers.add(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: onBecomeActive))
        observers.add(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: onLeave))
        observers.add(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: onLeave))
        #elseif canImport(AppKit)
        observers.add(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: onBecomeActive))
        observers.add(center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main, using: onLeave))
        observers.add(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main, using: onLeave))
        #endif
    }
}

/// 저장소가 사라지면 알림 구독도 끊는다.
private nonisolated final class NotificationObservers {
    private var tokens: [any NSObjectProtocol] = []

    func add(_ token: any NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}
