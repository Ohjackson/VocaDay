import NaturalLanguage
import SwiftUI
import XCTest
@testable import VocaDay

final class FitTests: XCTestCase {
    private let lemmatizer = FitEnglishLemmatizer()

    private static let references = FitReferenceLists.englishBundled(bundle: .main)

    // MARK: 도우미

    private func book(id: String = "test", chapters: [[String]], translations: Bool = true, glossary: [GlossaryEntry] = []) -> BookDocument {
        BookDocument(
            formatVersion: 1,
            id: id,
            language: "en",
            title: "Test",
            subtitle: nil,
            author: nil,
            level: nil,
            summary: nil,
            chapters: chapters.enumerated().map { index, sentences in
                BookChapter(title: "Chapter \(index + 1)", paragraphs: [
                    BookParagraph(sentences: sentences.map { BookSentence(text: $0, translation: translations ? "번역" : nil) }),
                ])
            },
            glossary: glossary
        )
    }

    private func sampleBook() throws -> BookDocument {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-first-week", withExtension: "json"), "샘플 책이 번들에 없다")
        return try JSONDecoder().decode(BookDocument.self, from: Data(contentsOf: url))
    }

    private func analyzer(references: FitReferenceLists = FitTests.references, criteria: BookFitCriteria = .standard) -> BookFitAnalyzer {
        BookFitAnalyzer(lemmatizer: lemmatizer, references: references, criteria: criteria)
    }

    // MARK: 원형 세기

    func testCountsLemmaOfInflectedForms() {
        let tokens = lemmatizer.tokens(in: "Her manager had already allocated a desk, and the suppliers were reviewing contracts.")
        let keys = Dictionary(tokens.map { ($0.surface, $0.keys) }, uniquingKeysWith: { first, _ in first })
        XCTAssertTrue(keys["allocated"]?.contains("allocate") == true, "\(keys["allocated"] ?? [])")
        XCTAssertTrue(keys["suppliers"]?.contains("supplier") == true)
        XCTAssertTrue(keys["reviewing"]?.contains("review") == true)
        XCTAssertFalse(tokens.contains { $0.surface == "," }, "기호는 토큰이 아니다")
        // 원형 모델이 있는 곳(macOS, 실기기)에서는 대표 원형이 바로 원형이다. iOS 시뮬레이터에는 모델이 없을 수 있다.
        if Self.taggerHasLemmaModel {
            let lemmas = Dictionary(tokens.map { ($0.surface, $0.lemma) }, uniquingKeysWith: { first, _ in first })
            XCTAssertEqual(lemmas["allocated"], "allocate")
            XCTAssertEqual(lemmas["had"], "have")
        }
    }

    private static var taggerHasLemmaModel: Bool {
        let text = "She was planning trips."
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        return tagger.tag(at: text.startIndex, unit: .word, scheme: .lemma).0 != nil
    }

    func testRuleCandidatesCoverRegularInflections() {
        XCTAssertTrue(FitEnglishLemmatizer.inflectionCandidates("allocated").contains("allocate"))
        XCTAssertTrue(FitEnglishLemmatizer.inflectionCandidates("planning").contains("plan"))
        XCTAssertTrue(FitEnglishLemmatizer.inflectionCandidates("companies").contains("company"))
        XCTAssertTrue(FitEnglishLemmatizer.inflectionCandidates("contracts").contains("contract"))
        XCTAssertFalse(FitEnglishLemmatizer.inflectionCandidates("manager").contains("manage"))
    }

    func testStripsContractionsAndPossessives() {
        XCTAssertEqual(FitEnglishLemmatizer.stripClitics("didn't"), "did")
        XCTAssertEqual(FitEnglishLemmatizer.stripClitics("can't"), "can")
        XCTAssertEqual(FitEnglishLemmatizer.stripClitics("won't"), "will")
        XCTAssertEqual(FitEnglishLemmatizer.stripClitics("mina's"), "mina")
        XCTAssertEqual(FitEnglishLemmatizer.stripClitics("they're"), "they")
        XCTAssertEqual(lemmatizer.normalize("Manager’s"), "manager's")
    }

    func testNumbersAreNotCounted() {
        let tokens = lemmatizer.tokens(in: "She reviewed 12 contracts at 3.5 percent.")
        XCTAssertTrue(tokens.contains { $0.surface == "12" && $0.kind == .number })
        XCTAssertFalse(tokens.contains { $0.surface == "12" && $0.kind == .word })
    }

    func testAllocatedCountsAsKnownWhenLemmaIsKnown() {
        let profile = VocabularyProfile(known: ["the", "manager", "allocate", "a", "desk"])
        let report = analyzer(references: .empty).analyze(book(chapters: [["The manager allocated a desk."]]), profile: profile)
        XCTAssertEqual(report.overall.tokenCount, 5)
        XCTAssertEqual(report.overall.knownCount, 5)
    }

    // MARK: 고유명사

    func testProperNounsAreExcludedFromCoverage() {
        let profile = VocabularyProfile(known: ["arrive", "at", "the", "office", "by", "friday", "have", "finish", "review", "all", "contract", "we", "send", "to"])
        // 불규칙 활용(had, sent)은 원형 모델이 없는 시뮬레이터에서도 NGSL 변화형으로 맞춘다.
        let report = analyzer().analyze(book(chapters: [[
            "Mina arrived at the office.",
            "By Friday, Mina had finished reviewing all the contracts.",
            "We sent the contract to Pellworth.",
        ]]), profile: profile)
        XCTAssertEqual(report.overall.properNounCount, 3, "Mina 두 번(문장 첫머리 포함) + 태거가 모를 수 있는 Pellworth")
        XCTAssertEqual(report.overall.coverage, 1, accuracy: 0.0001, "\(report.unknownWords.map(\.word))")
        XCTAssertFalse(report.unknownWords.contains { $0.word.lowercased() == "mina" })
    }

    func testCapitalizedCommonWordAtSentenceStartIsStillCounted() {
        let profile = VocabularyProfile(known: ["meeting", "start", "at", "noon", "the"])
        let report = analyzer(references: .empty).analyze(book(chapters: [["Meetings start at noon.", "The meeting starts at noon."]]), profile: profile)
        XCTAssertEqual(report.overall.properNounCount, 0)
        XCTAssertEqual(report.overall.knownCount, report.overall.tokenCount)
    }

    // MARK: 판정 경계값

    func testVerdictBoundaries() {
        let criteria = BookFitCriteria.standard
        XCTAssertEqual(criteria.verdict(coverage: 0.98), .extensive)
        XCTAssertEqual(criteria.verdict(coverage: 0.9799), .intensive)
        XCTAssertEqual(criteria.verdict(coverage: 0.95), .intensive)
        XCTAssertEqual(criteria.verdict(coverage: 0.9499), .notYet)
        XCTAssertEqual(criteria.verdict(coverage: Double(95) / Double(100)), .intensive)
        XCTAssertEqual(criteria.verdict(coverage: Double(49) / Double(50)), .extensive)
        XCTAssertEqual(BookFitCriteria(extensiveCoverage: 0.9, intensiveCoverage: 0.8).verdict(coverage: 0.85), .intensive, "기준값을 바꿀 수 있다")
    }

    /// 100단어 중 아는 단어 n개인 책.
    private func coverageBook(known: Int) -> BookDocument {
        let words = Array(repeating: "desk", count: known) + Array(repeating: "blorf", count: 100 - known)
        let sentences = stride(from: 0, to: 100, by: 10).map { words[$0..<$0 + 10].joined(separator: " ") + "." }
        return book(chapters: [sentences])
    }

    func testVerdictBoundariesThroughAnalyzer() {
        let profile = VocabularyProfile(known: ["desk"])
        let analyzer = analyzer(references: .empty)
        let cases: [(Int, BookFitVerdict)] = [(98, .extensive), (97, .intensive), (95, .intensive), (94, .notYet)]
        for (known, expected) in cases {
            let report = analyzer.analyze(coverageBook(known: known), profile: profile)
            XCTAssertEqual(report.overall.tokenCount, 100)
            XCTAssertEqual(report.overall.knownCount, known)
            XCTAssertEqual(report.verdict, expected, "\(known)%")
            XCTAssertEqual(report.chapters.first?.stats.verdict, expected)
        }
        XCTAssertEqual(analyzer.analyze(coverageBook(known: 95), profile: profile).overall.unknownPerThousand, 50, accuracy: 0.001)
    }

    // MARK: 복습 단어

    func testReviewWordsReappearAndAreNotCountedAsKnown() throws {
        let book = try sampleBook()
        let profile = VocabularyProfile(
            wordbook: [
                WordbookEntry(word: "allocate", stage: 2),
                WordbookEntry(word: "review", stage: 0),
                WordbookEntry(word: "deadline", stage: 6),
                WordbookEntry(word: "supplier", stage: 1),
                WordbookEntry(word: "supplier", stage: 7),
            ],
            references: Self.references,
            lemmatizer: lemmatizer
        )
        XCTAssertTrue(profile.isLearning("allocate"))
        XCTAssertTrue(profile.isLearning("review"), "고빈도 목록에 있어도 단어장에서 외우는 중이면 외우는 중")
        XCTAssertTrue(profile.isKnown("deadline"))
        XCTAssertTrue(profile.isKnown("supplier"), "같은 단어가 여러 번 있으면 높은 단계")

        let report = analyzer().analyze(book, profile: profile)
        let review = Dictionary(uniqueKeysWithValues: report.reviewWords.map { ($0.word, $0.count) })
        XCTAssertEqual(review["allocate"], 1)
        XCTAssertEqual(review["review"], 2, "review + reviewing")
        XCTAssertNil(review["deadline"])
        XCTAssertEqual(report.overall.reviewTokenCount, 3)
        XCTAssertEqual(report.reviewWords.first { $0.word == "allocate" }?.firstPosition, ReadingPosition(chapter: 0, paragraph: 0, sentence: 1))
    }

    func testAdjustmentsOverrideProfile() {
        let profile = VocabularyProfile(
            wordbook: [WordbookEntry(word: "allocate", stage: 1)],
            references: .empty,
            lemmatizer: lemmatizer,
            adjustments: .init(assumeKnown: ["allocate"], assumeUnknown: ["desk"])
        )
        XCTAssertTrue(profile.isKnown("allocate"))
        XCTAssertFalse(profile.isLearning("allocate"))
        XCTAssertFalse(profile.isKnown("desk"))
    }

    func testProfileFromAppWordReadsStageOnly() {
        let word = VocaWord(english: "Allocate")
        word.srsStage = 6
        let entry = WordbookEntry(word)
        XCTAssertEqual(entry, WordbookEntry(word: "Allocate", stage: 6))
        XCTAssertEqual(word.srsStage, 6)
        let profile = VocabularyProfile(wordbook: [entry], references: .empty, lemmatizer: lemmatizer)
        XCTAssertTrue(profile.isKnown("allocate"))
    }

    // MARK: 품질 경고

    func testQualityWarnings() {
        let long = Array(repeating: "word", count: 61).joined(separator: " ") + "."
        var book = book(chapters: [[
            "To: All staff",
            "We met at noon",
            "Th\u{FFFD}s is broken.",
            long,
            "The supplier sent the invoice.",
            "Please check the invoice.",
        ]], glossary: [
            GlossaryEntry(lemma: "invoice", forms: ["invoice"], partOfSpeech: "n.", meaning: "청구서", firstPosition: ReadingPosition(chapter: 0, paragraph: 0, sentence: 5)),
            GlossaryEntry(lemma: "supplier", forms: ["supplier"], partOfSpeech: "n.", meaning: "공급업체", firstPosition: ReadingPosition(chapter: 0, paragraph: 0, sentence: 1)),
            GlossaryEntry(lemma: "deadline", forms: ["deadline"], partOfSpeech: "n.", meaning: "마감", firstPosition: ReadingPosition(chapter: 3, paragraph: 0, sentence: 0)),
            GlossaryEntry(lemma: "staff", forms: ["staff"], partOfSpeech: "n.", meaning: "직원", firstPosition: ReadingPosition(chapter: 0, paragraph: 0, sentence: 0)),
        ])
        book.chapters[0].paragraphs[0].sentences[4].translation = nil
        book.chapters[0].paragraphs[0].sentences[5].translation = "  "

        let report = analyzer().analyze(book, profile: VocabularyProfile(known: []))
        XCTAssertEqual(report.warningCount(.missingTranslation), 2)
        XCTAssertEqual(report.warningCount(.longSentence), 1)
        XCTAssertEqual(report.warningCount(.unterminatedSentence), 1, "머리줄 'To: …' 은 마침표가 없어도 된다")
        XCTAssertEqual(report.quality.first { $0.kind == .unterminatedSentence }?.positions, [ReadingPosition(chapter: 0, paragraph: 0, sentence: 1)])
        XCTAssertEqual(report.warningCount(.garbledText), 1)
        XCTAssertGreaterThan(report.garbledRatio, 0)
        XCTAssertEqual(report.quality.first { $0.kind == .glossaryPositionInvalid }?.details.sorted(), ["deadline", "supplier"])
        XCTAssertEqual(report.quality.first { $0.kind == .glossaryPositionNotFirst }?.details, ["invoice"])
        XCTAssertEqual(report.sentenceProblemCount, 3)
    }

    func testSampleBookHasNoQualityWarnings() throws {
        let report = analyzer().analyze(try sampleBook(), profile: VocabularyProfile(known: []))
        for warning in report.quality {
            XCTAssertEqual(warning.count, 0, warning.kind.title)
        }
    }

    // MARK: 캐시

    func testCacheReusesAndInvalidatesReports() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BookFitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = BookFitService(analyzer: analyzer(), cache: BookFitCache(directory: directory), classifier: nil)
        let book = try sampleBook()
        let profile = VocabularyProfile(wordbook: [WordbookEntry(word: "allocate", stage: 1)], references: Self.references, lemmatizer: lemmatizer)

        let first = await service.report(for: book, profile: profile)
        let again = await service.report(for: book, profile: profile)
        XCTAssertEqual(first.generatedAt, again.generatedAt, "같은 책·같은 프로필은 캐시")

        // 단어장이 바뀜 (allocate 가 익숙해짐) → 다시 계산.
        let learned = VocabularyProfile(wordbook: [WordbookEntry(word: "allocate", stage: 5)], references: Self.references, lemmatizer: lemmatizer)
        XCTAssertNotEqual(learned.version, profile.version)
        let afterLearning = await service.report(for: book, profile: learned)
        XCTAssertNotEqual(afterLearning.cacheKey, first.cacheKey)
        XCTAssertTrue(afterLearning.reviewWords.isEmpty)
        XCTAssertGreaterThan(afterLearning.overall.knownCount, first.overall.knownCount)

        // 같은 ID 로 내용이 바뀐 책 → 다시 계산.
        var edited = book
        edited.chapters[0].paragraphs[0].sentences[0].text = "Mina arrived at the office early."
        let afterEdit = await service.report(for: edited, profile: learned)
        XCTAssertNotEqual(afterEdit.cacheKey, afterLearning.cacheKey)

        // 디스크 캐시: 새 캐시 객체도 마지막 보고서를 읽는다.
        let reopened = BookFitService(analyzer: analyzer(), cache: BookFitCache(directory: directory), classifier: nil)
        let fromDisk = await reopened.report(for: edited, profile: learned)
        XCTAssertEqual(fromDisk.generatedAt.timeIntervalSince1970, afterEdit.generatedAt.timeIntervalSince1970, accuracy: 0.001)

        // 판정 기준이 바뀌어도 다시 계산.
        let strict = BookFitService(analyzer: analyzer(criteria: BookFitCriteria(extensiveCoverage: 0.99, intensiveCoverage: 0.97)), cache: BookFitCache(directory: directory), classifier: nil)
        let strictReport = await strict.report(for: edited, profile: learned)
        XCTAssertNotEqual(strictReport.cacheKey, afterEdit.cacheKey)
    }

    func testTopicsAreAttachedFromClassifierAndCached() async throws {
        let classifier = StubClassifier()
        let service = BookFitService(analyzer: analyzer(), cache: BookFitCache(directory: nil), classifier: classifier)
        let book = try sampleBook()
        let profile = VocabularyProfile(known: [])
        let report = await service.report(for: book, profile: profile)
        XCTAssertNil(report.topics)

        let classified = await service.addingTopics(to: report, book: book)
        XCTAssertEqual(classified.topics?.chapters.count, 2)
        XCTAssertEqual(classified.topics?.chapters.first??.genres, [.narrative])
        XCTAssertEqual(try XCTUnwrap(classified.topics?.examSituationShare), 1, accuracy: 0.001)

        // 단어장이 바뀌어 보고서를 다시 계산해도 주제는 다시 분류하지 않고 붙는다.
        let other = await service.report(for: book, profile: VocabularyProfile(known: ["the"]))
        XCTAssertNotNil(other.topics)
        let calls = await classifier.counter.value
        XCTAssertEqual(calls, 2)
    }

    func testUnavailableClassifierLeavesTopicsEmpty() async throws {
        var classifier = StubClassifier()
        classifier.isAvailable = false
        let service = BookFitService(analyzer: analyzer(), cache: BookFitCache(directory: nil), classifier: classifier)
        let book = try sampleBook()
        let report = await service.report(for: book, profile: VocabularyProfile(known: []))
        let result = await service.addingTopics(to: report, book: book)
        XCTAssertNil(result.topics)
    }

    // MARK: 단어 목록

    func testBundledWordListsLoad() {
        let references = Self.references
        XCTAssertEqual(references.general.count, 2809)
        XCTAssertEqual(references.general.headwords.first, "the")
        XCTAssertEqual(references.general.formIndex["allocated"], nil, "allocate 는 NGSL 밖")
        XCTAssertEqual(references.exam.formIndex["allocated"], "allocate", "TSL")
        XCTAssertEqual(references.general.formIndex["was"], "be")
        XCTAssertNotNil(references.exam.formIndex["suppliers"])
        XCTAssertGreaterThanOrEqual(references.exam.count, 1250)
    }

    // MARK: 샘플 보고서 (출력 확인용)

    /// 샘플 책 + 책 폴더의 책(있으면)을 세 가지 프로필로 재서 출력한다. 책 폴더는 xcodebuild 환경 변수 `TEST_RUNNER_FIT_BOOKS_DIR` 로 넘긴다 (테스트에는 `FIT_BOOKS_DIR` 로 보인다).
    func testPrintSampleReports() throws {
        var books = [try sampleBook()]
        if let dir = ProcessInfo.processInfo.environment["FIT_BOOKS_DIR"] {
            let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? []
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("sample") {
                if let book = try? JSONDecoder().decode(BookDocument.self, from: Data(contentsOf: url)) { books.append(book) }
            }
        }
        let withBundled = Self.references
        let withoutBundled = FitReferenceLists.englishBundled(bundle: .main, includeBundledWords: false)
        let bundledWords = FitReferenceLists.bundledWordHeadwords(bundle: .main, normalize: lemmatizer.normalize)

        let setups: [(String, FitReferenceLists, [WordbookEntry])] = [
            ("빈 단어장 · 기본 단어장 파일 없음", withoutBundled, []),
            ("빈 단어장 · 기본 단어장 파일 있음", withBundled, []),
            ("기본 단어장 앞 200개 익숙함 + 다음 100개 외우는 중", withBundled,
             bundledWords.prefix(200).map { WordbookEntry(word: $0, stage: 6) } + bundledWords.dropFirst(200).prefix(100).map { WordbookEntry(word: $0, stage: 2) }),
        ]
        var output: [String] = []
        for book in books {
            for (name, references, wordbook) in setups {
                let profile = VocabularyProfile(wordbook: wordbook, references: references, lemmatizer: lemmatizer)
                let start = Date()
                let report = BookFitAnalyzer(references: references).analyze(book, profile: profile)
                output.append(Self.describe(report, setup: name, seconds: Date().timeIntervalSince(start)))
            }
        }
        print(output.joined(separator: "\n"))
        // xcodebuild 환경 변수 TEST_RUNNER_FIT_REPORT_OUT 으로 파일 경로를 주면 거기에도 쓴다.
        // macOS 샌드박스에서는 밖에 쓸 수 없어 컨테이너 임시 폴더에도 쓴다.
        let text = output.joined(separator: "\n")
        if let path = ProcessInfo.processInfo.environment["FIT_REPORT_OUT"] {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        try? text.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("fit-report.txt"), atomically: true, encoding: .utf8)
    }

    /// 배지·상세 화면을 PNG 로 그린다. xcodebuild 환경 변수 TEST_RUNNER_FIT_SNAPSHOT_DIR 이 있을 때만.
    @MainActor
    func testRenderSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["FIT_SNAPSHOT_DIR"] else {
            throw XCTSkip("FIT_SNAPSHOT_DIR 이 없으면 건너뛴다.")
        }
        let book = try sampleBook()
        var report = analyzer().analyze(book, profile: VocabularyProfile(
            wordbook: [WordbookEntry(word: "allocate", stage: 1), WordbookEntry(word: "review", stage: 2), WordbookEntry(word: "deadline", stage: 6)],
            references: Self.references,
            lemmatizer: lemmatizer
        ))
        report.topics = BookFitReport.preview.topics
        let views: [(String, AnyView, CGFloat)] = [
            ("badge-full", AnyView(BookFitBadge(report: report).padding()), 393),
            ("badge-compact", AnyView(BookFitBadge(report: report, style: .compact).padding()), 393),
            ("badge-preview", AnyView(BookFitBadge(report: .preview).padding()), 393),
            ("detail-phone", AnyView(BookFitDetailSections(report: report).padding().background(AppTheme.background)), 393),
            ("detail-wide", AnyView(BookFitDetailSections(report: .preview).padding().background(AppTheme.background)), 820),
        ]
        for (name, view, width) in views {
            let renderer = ImageRenderer(content: view.frame(width: width).environment(\.colorScheme, .light))
            renderer.scale = 2
            #if os(macOS)
            let data = renderer.nsImage?.tiffRepresentation
            #else
            let data = renderer.uiImage?.pngData()
            #endif
            try XCTUnwrap(data).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    static func describe(_ report: BookFitReport, setup: String, seconds: Double) -> String {
        let o = report.overall
        var lines = [
            "FITREPORT ===== \(report.bookTitle) [\(report.bookID)] · \(setup) · \(String(format: "%.2fs", seconds))",
            "FITREPORT \(report.verdict.title) · 아는 단어 \(BookFitFormat.percent(o.coverage)) · 모르는 단어 1,000당 \(BookFitFormat.perThousand(o.unknownPerThousand)) · 센 단어 \(o.tokenCount) (이름 \(o.properNounCount), 숫자 \(o.numberCount) 제외) · 평균 문장 \(String(format: "%.1f", o.averageSentenceLength))단어",
            "FITREPORT 토익 단어 \(o.examTypeCount)종 (1,000단어당 \(BookFitFormat.perThousand(o.examPerThousand))회) · 복습 단어 \(report.reviewWords.count)개 재등장 · 목록 \(report.referenceSources.joined(separator: ", "))",
            "FITREPORT 경고: " + report.quality.map { "\($0.kind.title) \($0.count)" }.joined(separator: " · "),
        ]
        for chapter in report.chapters {
            lines.append("FITREPORT   \(chapter.index + 1). \(chapter.title): \(BookFitFormat.percent(chapter.stats.coverage)) \(chapter.stats.verdict.title) · 토익 \(chapter.stats.examTypeCount)종")
        }
        lines.append("FITREPORT 모르는 단어 상위: " + report.unknownWords.prefix(15).map { "\($0.word)×\($0.count)" }.joined(separator: ", "))
        lines.append("FITREPORT 복습 단어: " + report.reviewWords.prefix(15).map { "\($0.word)×\($0.count)" }.joined(separator: ", "))
        for warning in report.quality where warning.count > 0 && !warning.details.isEmpty {
            lines.append("FITREPORT   \(warning.kind.title): " + warning.details.prefix(8).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

private actor CallCounter {
    var value = 0
    func increment() { value += 1 }
}

nonisolated private struct StubClassifier: BookTopicClassifying {
    var identifier: String { "stub" }
    var isAvailable = true
    let counter = CallCounter()

    func classify(chapterTitle: String, text: String) async throws -> ChapterTopic {
        await counter.increment()
        return ChapterTopic(isExamSituation: true, genres: [.narrative], situation: chapterTitle)
    }
}
