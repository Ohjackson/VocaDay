import Foundation

/// 학습일 안에서의 위치. 같은 학습일이면 1차 세션 다음이 재도전이다.
nonisolated struct StudyDayKey: Comparable, Sendable {
    var learningDay: Int
    var kind: SRSSessionKind

    static func < (lhs: StudyDayKey, rhs: StudyDayKey) -> Bool {
        if lhs.learningDay != rhs.learningDay { return lhs.learningDay < rhs.learningDay }
        return lhs.kind == .first && rhs.kind == .retry
    }
}

/// 기기 사이에서 합칠 수 있는 학습 기록. 두 기기가 서로의 값을 받아 합친 결과가 같아야 한다 (교환 법칙).
nonisolated protocol StudySyncValue: Codable, Equatable, Sendable {
    /// 같은 키에 저장된 다른 기기의 값과 합친다.
    func merged(with other: Self) -> Self
    /// 순서 배열을 빼고 내용이 같은지. 다르면 합친 값을 iCloud에 다시 올린다.
    func hasSameContent(as other: Self) -> Bool
}

/// 오늘 장부·시험 이어하기를 iCloud 키-값 저장소로 기기 사이에 나눈다.
///
/// 읽기는 항상 기기 로컬(UserDefaults)에서 한다 — 화면이 `@AppStorage`로 같은 키를 지켜본다.
/// 쓰면 로컬과 iCloud에 함께 쓰고, 다른 기기의 변경이 오면 로컬 값과 합쳐 로컬에 쓴다.
nonisolated struct SyncedStudyStorage<Value: StudySyncValue>: Sendable {
    let storageKey: String
    /// false면 기기에만 둔다 (테스트).
    let syncsWithICloud: Bool

    private var defaults: UserDefaults { .standard }
    private var cloud: NSUbiquitousKeyValueStore { .default }
    /// iCloud 키-값 저장소는 앱 전체 1MB 한도라 큰 값은 올리지 않는다.
    private static var cloudSizeLimit: Int { 256 * 1024 }

    func load() -> Value? {
        decode(defaults.data(forKey: storageKey))
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: storageKey)
        if syncsWithICloud, data.count <= Self.cloudSizeLimit {
            cloud.set(data, forKey: storageKey)
        }
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
        if syncsWithICloud {
            cloud.removeObject(forKey: storageKey)
        }
    }

    /// iCloud 값을 로컬과 합친다.
    /// - Parameter changedExternally: 다른 기기가 이 키를 바꿨다는 알림. 이때 값이 없으면 그 기기에서 지운 것이다.
    func mergeFromCloud(changedExternally: Bool) {
        guard syncsWithICloud else { return }
        let local = load()
        guard let remote = decode(cloud.data(forKey: storageKey)) else {
            if changedExternally, cloud.object(forKey: storageKey) == nil {
                defaults.removeObject(forKey: storageKey)
            } else if let local {
                save(local)
            }
            return
        }
        guard let local else {
            if let data = try? JSONEncoder().encode(remote) {
                defaults.set(data, forKey: storageKey)
            }
            return
        }
        let merged = local.merged(with: remote)
        if merged != local, let data = try? JSONEncoder().encode(merged) {
            defaults.set(data, forKey: storageKey)
        }
        if !merged.hasSameContent(as: remote) {
            save(merged)
        }
    }

    private func decode(_ data: Data?) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}

/// 다른 기기에서 바뀐 장부·이어하기를 받아 합친다. 앱 시작 때 한 번 켠다.
enum StudySessionSync {
    private static var observer: NSObjectProtocol?

    static func start() {
        guard observer == nil else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { notification in
            let keys = Set(notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? [])
            MainActor.assumeIsolated {
                mergeAll(changedKeys: keys)
            }
        }
        cloud.synchronize()
        mergeAll(changedKeys: [])
    }

    private static func mergeAll(changedKeys: Set<String>) {
        let ledger = StudyDayLedgerStore.standard
        ledger.mergeFromCloud(changedExternally: changedKeys.contains(ledger.storageKey))
        let exam = ExamSessionStore.standard
        exam.mergeFromCloud(changedExternally: changedKeys.contains(exam.storageKey))
    }
}

// MARK: - 합치기 규칙

/// 같은 단어를 두 기기에서 다르게 채점했으면 틀린 쪽으로 본다 (어느 기기에서 합쳐도 같은 결과).
private nonisolated func mergeResults(
    _ mine: [String: Bool],
    order mineOrder: [String],
    with other: [String: Bool],
    order otherOrder: [String]
) -> (results: [String: Bool], order: [String]) {
    var results = mine
    var order = mineOrder
    for key in otherOrder {
        guard let value = other[key] else { continue }
        if let existing = results[key] {
            results[key] = existing && value
        } else {
            results[key] = value
            order.append(key)
        }
    }
    return (results, order)
}

/// 같은 키가 다르면 문자열이 작은 쪽을 쓴다 (어느 기기에서 합쳐도 같은 결과).
private nonisolated func mergeLabels(_ mine: [String: String], _ other: [String: String]) -> [String: String] {
    mine.merging(other) { min($0, $1) }
}

nonisolated extension StudyDayLedger: StudySyncValue {
    var dayKey: StudyDayKey { StudyDayKey(learningDay: learningDay, kind: kind) }

    func merged(with other: StudyDayLedger) -> StudyDayLedger {
        if dayKey != other.dayKey { return dayKey > other.dayKey ? self : other }
        var merged = self
        (merged.results, merged.order) = mergeResults(results, order: order, with: other.results, order: other.order)
        merged.sessionID = sessionID.uuidString < other.sessionID.uuidString ? sessionID : other.sessionID
        merged.modes = mergeLabels(modes, other.modes)
        merged.details = mergeLabels(details, other.details)
        merged.updatedAt = [updatedAt, other.updatedAt].compactMap { $0 }.max()
        merged.finalizedAt = [finalizedAt, other.finalizedAt].compactMap { $0 }.max()
        return merged
    }

    func hasSameContent(as other: StudyDayLedger) -> Bool {
        var lhs = self, rhs = other
        lhs.order = []
        rhs.order = []
        return lhs == rhs
    }
}

nonisolated extension ActiveExamSession: StudySyncValue {
    var dayKey: StudyDayKey { StudyDayKey(learningDay: learningDay, kind: kind) }

    func merged(with other: ActiveExamSession) -> ActiveExamSession {
        if dayKey != other.dayKey { return dayKey > other.dayKey ? self : other }
        guard sessionID == other.sessionID else {
            // 두 기기가 따로 계획했다. 더 많이 푼 쪽을 이어 한다 (결과는 장부에서 합쳐진다).
            let mine = (cursor, answeredGradedCount, sessionID.uuidString)
            let theirs = (other.cursor, other.answeredGradedCount, other.sessionID.uuidString)
            return mine >= theirs ? self : other
        }
        var merged = self
        merged.cursor = max(cursor, other.cursor)
        (merged.results, merged.resultOrder) = mergeResults(results, order: resultOrder, with: other.results, order: other.resultOrder)
        if details != nil || other.details != nil {
            merged.details = mergeLabels(details ?? [:], other.details ?? [:])
        }
        if hintedWordIDs != nil || other.hintedWordIDs != nil {
            let mine = hintedWordIDs ?? []
            merged.hintedWordIDs = mine + (other.hintedWordIDs ?? []).filter { !mine.contains($0) }
        }
        return merged
    }

    func hasSameContent(as other: ActiveExamSession) -> Bool {
        var lhs = self, rhs = other
        lhs.resultOrder = []
        rhs.resultOrder = []
        lhs.hintedWordIDs = lhs.hintedWordIDs.map { $0.sorted() }
        rhs.hintedWordIDs = rhs.hintedWordIDs.map { $0.sorted() }
        return lhs == rhs
    }
}
