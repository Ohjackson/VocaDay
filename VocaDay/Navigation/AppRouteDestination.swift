import SwiftData
import SwiftUI

/// 코드에서 화면을 push 할 때 쓰는 동작입니다. (`NavigationLink(value:)` 를 쓸 수 없는 경우에만)
struct AppNavigateAction {
    fileprivate let handler: (AppRoute) -> Void

    init(_ handler: @escaping (AppRoute) -> Void) {
        self.handler = handler
    }

    func callAsFunction(_ route: AppRoute) {
        handler(route)
    }
}

extension EnvironmentValues {
    @Entry var appNavigate = AppNavigateAction { _ in }
}

extension View {
    /// 각 섹션 NavigationStack 의 루트에 한 번만 붙입니다.
    func appRouteDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            AppRouteDestination(route: route)
        }
    }
}

/// `AppRoute` 를 실제 화면으로 바꿉니다. 모델은 ID 로 다시 조회합니다.
struct AppRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .settings:
            SettingsView()
        case .settingsBackup:
            JSONBackupView()
        case .settingsPrivacy:
            PrivacyAndServiceView()
        case .addWordsHelp:
            AddWordsHelpView()
        case .dayWords(let dayID):
            DayRouteResolver(dayID: dayID) { day in
                DayWordsDetailView(initialDay: day)
            }
        case .reviewSession(let dayID, let dueOnly):
            DayRouteResolver(dayID: dayID) { day in
                ReviewSessionView(day: day, dueOnly: dueOnly)
            }
        case .studyMemo(let memoID):
            StudyMemoRouteResolver(memoID: memoID)
        case .wordStudyDetail(let wordID):
            WordStudyDetailRouteResolver(wordID: wordID)
        case .examSession:
            // 세션 화면에 자체 닫기 버튼과 진행 바가 있으므로 시스템 뒤로 가기는 숨깁니다.
            ExamSessionView()
                .navigationBarBackButtonHidden(true)
                .toolbar(removing: .title)
        }
    }
}

private struct DayRouteResolver<Content: View>: View {
    @Query private var days: [VocabularyDay]
    private let content: (VocabularyDay) -> Content

    init(dayID: UUID, @ViewBuilder content: @escaping (VocabularyDay) -> Content) {
        _days = Query(filter: #Predicate<VocabularyDay> { $0.id == dayID })
        self.content = content
    }

    var body: some View {
        if let day = days.first {
            content(day)
        } else {
            ContentUnavailableView("데이를 찾을 수 없습니다", systemImage: "calendar")
        }
    }
}

private struct StudyMemoRouteResolver: View {
    @Query private var memos: [StudyMemo]

    init(memoID: UUID) {
        _memos = Query(filter: #Predicate<StudyMemo> { $0.id == memoID })
    }

    var body: some View {
        if let memo = memos.first {
            StudyPageEditorView(memo: memo)
        } else {
            ContentUnavailableView("페이지를 찾을 수 없습니다", systemImage: "doc.text")
        }
    }
}

private struct WordStudyDetailRouteResolver: View {
    let wordID: UUID

    @Query private var words: [VocaWord]
    @Query private var progressRecords: [StudyProgress]
    @Query(sort: \ReviewLog.answeredAt) private var logs: [ReviewLog]

    var body: some View {
        if let word = words.first(where: { $0.id == wordID }) {
            WordStudyDetailView(
                word: word,
                stats: StudyStats(
                    words: words.map(\.statsWord),
                    session: StudyProgressStore.preferred(progressRecords)?.sessionState ?? .initial
                ),
                history: ReviewHistoryStats(entries: logs.map(\.entry))
            )
        } else {
            ContentUnavailableView("단어를 찾을 수 없습니다", systemImage: "textformat")
        }
    }
}
