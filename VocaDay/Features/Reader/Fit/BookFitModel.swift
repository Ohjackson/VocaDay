import Foundation
import Observation
import SwiftData
import SwiftUI

extension BookFitService {
    /// 영어(VocaDay) 구성. 단어 목록은 처음 쓸 때 한 번 읽는다.
    nonisolated static let english: BookFitService = BookFitService(
        analyzer: BookFitAnalyzer(references: .englishBundled()),
        cache: BookFitCache(directory: BookFitCache.defaultDirectory()),
        classifier: FoundationModelsTopicClassifier()
    )
}

// MARK: - 앱 데이터 어댑터 (SwiftData `VocaWord` → 코어 값)

extension WordbookEntry {
    /// SRS 필드는 읽기만 한다.
    init(_ word: VocaWord) {
        self.init(word: word.english, stage: word.srsStage)
    }
}

extension VocabularyProfile {
    /// 내 단어장 전체로 만든다. 메인 스레드에서 단어를 읽고, 집합 계산은 호출한 쪽 스레드에서 한다.
    static func entries(from context: ModelContext) -> [WordbookEntry] {
        let words = (try? context.fetch(FetchDescriptor<VocaWord>())) ?? []
        return words.map(WordbookEntry.init)
    }
}

// MARK: - 화면용 모델

/// 현재 단어장 프로필을 들고 있고, 책마다 보고서를 돌려준다. 단어장이 저장되면 프로필을 다시 만든다.
@Observable
final class BookFitModel {
    static let shared = BookFitModel(service: .english)

    let service: BookFitService
    var settings: VocabularyProfile.Settings = .standard {
        didSet { if settings != oldValue { scheduleRefresh(delay: .zero) } }
    }
    /// 나중에 읽는 중 기록으로 채운다.
    var adjustments: VocabularyProfile.Adjustments = .none {
        didSet { if adjustments != oldValue { scheduleRefresh(delay: .zero) } }
    }
    /// 바뀌면 화면이 보고서를 다시 요청한다.
    private(set) var profileVersion: String = ""
    private(set) var profile: VocabularyProfile?

    @ObservationIgnored private weak var context: ModelContext?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var saveObserver: NSObjectProtocol?

    init(service: BookFitService) {
        self.service = service
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(delay: .seconds(1)) }
        }
    }

    /// 화면이 나타날 때 부른다. 프로필이 없으면 만든다.
    func prepare(context: ModelContext) async {
        if self.context == nil { self.context = context }
        guard profile == nil else { return }
        if let refreshTask {
            await refreshTask.value
        } else {
            await refresh()
        }
    }

    func report(for book: BookDocument) async -> BookFitReport? {
        guard let profile else { return nil }
        return await service.report(for: book, profile: profile)
    }

    func addingTopics(to report: BookFitReport, book: BookDocument) async -> BookFitReport {
        await service.addingTopics(to: report, book: book)
    }

    var canClassifyTopics: Bool { service.classifier?.isAvailable == true }

    private func scheduleRefresh(delay: Duration) {
        guard context != nil else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        guard let context else { return }
        let entries = VocabularyProfile.entries(from: context)
        let references = service.references
        let settings = settings
        let adjustments = adjustments
        let profile = await Task.detached(priority: .utility) {
            VocabularyProfile(wordbook: entries, references: references, lemmatizer: FitEnglishLemmatizer(), settings: settings, adjustments: adjustments)
        }.value
        guard !Task.isCancelled else { return }
        self.profile = profile
        if profileVersion != profile.version { profileVersion = profile.version }
    }
}

extension EnvironmentValues {
    /// 미리보기·테스트에서 바꿔 넣을 수 있다. 기본값은 `BookFitModel.shared`.
    @Entry var bookFitModel: BookFitModel = .shared
}
