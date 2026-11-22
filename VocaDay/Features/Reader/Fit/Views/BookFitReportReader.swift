import SwiftData
import SwiftUI

/// 책 하나의 보고서를 불러 와 `content` 에 넘긴다. 계산 중이면 nil.
/// 단어장이 저장되면(`ModelContext.didSave`) 프로필이 다시 만들어지고 보고서도 다시 계산된다.
///
/// 책 목록 카드:
/// ```swift
/// BookFitReportReader(book: book) { report in
///     if let report { BookFitBadge(report: report) }
/// }
/// ```
struct BookFitReportReader<Content: View>: View {
    let book: BookDocument
    @ViewBuilder var content: (BookFitReport?) -> Content

    @Environment(\.modelContext) private var modelContext
    @Environment(\.bookFitModel) private var model
    @State private var report: BookFitReport?

    var body: some View {
        content(report)
            .task(id: TaskKey(bookID: book.id, profileVersion: model.profileVersion)) {
                await model.prepare(context: modelContext)
                guard let fresh = await model.report(for: book), !Task.isCancelled else { return }
                report = fresh
            }
    }

    private struct TaskKey: Hashable {
        var bookID: String
        var profileVersion: String
    }
}

/// 상세 화면 본문. 보고서를 불러 오고, 기기 안 모델이 있으면 주제 분류 단추를 보인다.
/// push 할 화면에 그대로 둔다: `BookFitDetailScreen(book: book)`.
struct BookFitDetailScreen: View {
    let book: BookDocument

    @Environment(\.bookFitModel) private var model
    @State private var classified: BookFitReport?
    @State private var isClassifying = false

    var body: some View {
        BookFitReportReader(book: book) { report in
            if let report {
                let shown = classified.flatMap { $0.cacheKey == report.cacheKey ? $0 : nil } ?? report
                BookFitDetailView(
                    report: shown,
                    onClassifyTopics: model.canClassifyTopics ? { classify(shown) } : nil,
                    isClassifyingTopics: isClassifying
                )
            } else {
                ProgressView("적합도 계산 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("책 적합도")
    }

    private func classify(_ report: BookFitReport) {
        guard !isClassifying else { return }
        isClassifying = true
        Task {
            classified = await model.addingTopics(to: report, book: book)
            isClassifying = false
        }
    }
}

// MARK: - 미리보기 데이터

extension BookFitReport {
    static var preview: BookFitReport {
        var overall = BookFitStats()
        overall.tokenCount = 1_040
        overall.knownCount = 1_003
        overall.properNounCount = 42
        overall.numberCount = 9
        overall.sentenceCount = 96
        overall.averageSentenceLength = 11.4
        overall.examTypeCount = 41
        overall.examTokenCount = 19
        overall.reviewTokenCount = 15
        overall.verdict = .intensive

        var hard = overall
        hard.tokenCount = 300
        hard.knownCount = 282
        hard.verdict = .notYet

        return BookFitReport(
            bookID: "preview",
            bookTitle: "The First Week",
            language: "en",
            generatedAt: Date(),
            cacheKey: "preview",
            criteria: .standard,
            referenceSources: ["NGSL 2809", "TSL 1250", "기본 단어장 2391"],
            profileWordbookCount: 320,
            generalKnownCount: 2000,
            overall: overall,
            chapters: [
                ChapterFit(index: 0, title: "Monday", stats: overall),
                ChapterFit(index: 1, title: "Budget Meeting", stats: hard),
            ],
            examWords: [
                FitWordCount(word: "supplier", count: 4, firstPosition: .start),
                FitWordCount(word: "deadline", count: 3, firstPosition: .start),
                FitWordCount(word: "invoice", count: 2, firstPosition: .start),
            ],
            reviewWords: [
                FitWordCount(word: "allocate", count: 3, firstPosition: .start),
                FitWordCount(word: "itinerary", count: 2, firstPosition: .start),
            ],
            unknownWords: [FitWordCount(word: "reimburse", count: 2, firstPosition: .start)],
            quality: BookQualityWarning.Kind.allCases.map {
                BookQualityWarning(kind: $0, count: $0 == .unterminatedSentence ? 2 : 0, positions: $0 == .unterminatedSentence ? [.start] : [], details: [])
            },
            garbledRatio: 0,
            topics: BookTopicSummary(
                chapters: [
                    ChapterTopic(isExamSituation: true, genres: [.narrative, .email], situation: "신입 사원 첫 출근"),
                    ChapterTopic(isExamSituation: true, genres: [.conversation], situation: "예산 회의"),
                ],
                examSituationShare: 0.85,
                classifierIdentifier: "preview"
            )
        )
    }
}
