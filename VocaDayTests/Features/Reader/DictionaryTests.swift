import SwiftData
import SwiftUI
import XCTest
@testable import VocaDay

@MainActor
final class DictionaryTests: XCTestCase {
    // MARK: - 준비

    private struct FakeGenerator: EnglishWordGenerating {
        var availability: EnglishWordGenerationAvailability = .available
        var calls: Calls = Calls()

        final class Calls: @unchecked Sendable { var terms: [String] = [] }

        func generateWord(for input: String) async throws -> GeneratedEnglishWord {
            calls.terms.append(input)
            return GeneratedEnglishWord(
                word: input,
                meanings: [GeneratedWordMeaning(
                    partOfSpeech: .noun,
                    meaning: "창문",
                    englishExample: "Open the \(input), please.",
                    koreanExample: "창문을 열어 주세요."
                )],
                usageNote: "자주 쓰는 명사",
                toeicTag: "사무실",
                spellingCorrection: ""
            )
        }
    }

    private let bundled = BundledWordIndex.make([
        VocaWordJSON(english: "contract", meaningKo: "n. 계약, 계약서", note: "sign a contract", toeicTag: "office"),
        VocaWordJSON(english: "deadline", meaningKo: "n. 마감 기한 (기본 단어장)"),
    ])

    private func sampleBook() throws -> BookDocument {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-first-week", withExtension: "json"))
        return try JSONDecoder().decode(BookDocument.self, from: Data(contentsOf: url))
    }

    /// 테스트마다 비어 있는 생성 뜻 저장소.
    private func emptyMeaningStore() -> GeneratedMeaningStore {
        let suite = "DictionaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return GeneratedMeaningStore(defaults: defaults)
    }

    private lazy var meanings = emptyMeaningStore()

    private func pipeline() -> WordLookupPipeline {
        let index = bundled
        return EnglishWordLookup.pipeline(bundledWords: { index }, wiktionary: { [:] }, generatedMeanings: meanings, usesTranslation: false, usesSystemDictionary: false)
    }

    private func generation(generator: FakeGenerator = FakeGenerator(), enabled: Bool = true) -> GeneratedWordLookupStep {
        EnglishWordLookup.generation(generator: generator, isGenerationEnabled: { enabled }, generatedMeanings: meanings)
    }

    private func tap(_ surface: String, in book: BookDocument) -> WordTapContext {
        WordLookupCardPreview.context(surface: surface, book: book)
    }

    private func result(_ outcome: WordLookupOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> WordLookupResult {
        guard case .found(let result) = outcome else {
            XCTFail("못 찾음: \(outcome)", file: file, line: line)
            throw XCTSkip()
        }
        return result
    }

    // MARK: - 찾기 순서

    func testBookGlossaryComesFirst() async throws {
        let book = try sampleBook()
        // deadline은 기본 단어장에도 있지만 책 사전이 먼저다.
        let found = try result(await pipeline().lookup(tap("deadline", in: book), book: book))
        XCTAssertEqual(found.source, .bookGlossary)
        XCTAssertEqual(found.headword, "deadline")
        XCTAssertEqual(found.meaningForSaving, "n. 마감일, 기한")

        // 본문 모양이 forms에 있으면 그대로 찾는다.
        let allocated = try result(await pipeline().lookup(tap("allocated", in: book), book: book))
        XCTAssertEqual(allocated.source, .bookGlossary)
        XCTAssertEqual(allocated.headword, "allocate")
        XCTAssertTrue(allocated.showsLemma)
    }

    func testLemmaFindsGlossaryEntryWhenFormIsMissing() async throws {
        var book = try sampleBook()
        // forms에 "allocated"가 없는 책: 원형(allocate)으로 다시 찾아야 한다.
        book.glossary = book.glossary.map { entry in
            var entry = entry
            if entry.lemma == "allocate" { entry.forms = ["allocate"] }
            return entry
        }
        XCTAssertNil(book.glossaryEntry(forSurface: "allocated"))

        let context = tap("allocated", in: book)
        let request = pipeline().request(for: context, book: book)
        XCTAssertEqual(request.surface, "allocated")
        XCTAssertEqual(request.lemma, "allocate")

        let found = try result(await pipeline().lookup(context, book: book))
        XCTAssertEqual(found.source, .bookGlossary)
        XCTAssertEqual(found.headword, "allocate")
        XCTAssertEqual(found.surface, "allocated")
    }

    func testBundledPackComesAfterGlossaryAndUsesLemma() async throws {
        let book = try sampleBook()
        // contracts: 책 사전에 없고, 기본 단어장에는 원형 contract로 있다.
        let found = try result(await pipeline().lookup(tap("contracts", in: book), book: book))
        XCTAssertEqual(found.source, .bundledPack)
        XCTAssertEqual(found.headword, "contract")
        XCTAssertNil(found.partOfSpeech)
        XCTAssertEqual(found.meaningForSaving, "n. 계약, 계약서")
        XCTAssertEqual(found.note, "sign a contract")
    }

    func testAutoLookupNeverGeneratesAndUsesSavedMeaning() async throws {
        let book = try sampleBook()
        let context = tap("window", in: book)
        // 자동 찾기는 생성하지 않는다: JSON 데이터에 없으면 못 찾음.
        guard case .notFound = await pipeline().lookup(context, book: book) else { return XCTFail("생성 없이 찾음") }

        // 「⋯ → 기기에서 뜻 만들기」
        let generator = FakeGenerator()
        let step = generation(generator: generator)
        XCTAssertNil(step.unavailableReason)
        let generated = try await step.lookup(pipeline().request(for: context, book: book))
        let made = try XCTUnwrap(generated)
        XCTAssertEqual(made.source, .generated)
        XCTAssertEqual(made.headword, "window")
        XCTAssertEqual(made.meaningForSaving, "n. 창문")
        XCTAssertEqual(generator.calls.terms, ["window"])

        // 만든 뜻은 남아서 다음부터 자동으로 보인다 (다시 만들지 않는다).
        let again = try result(await pipeline().lookup(context, book: book))
        XCTAssertEqual(again.source, .generated)
        XCTAssertEqual(again.meaningForSaving, "n. 창문")
        XCTAssertEqual(generator.calls.terms, ["window"])

        // JSON 데이터에 있는 단어는 저장된 생성 뜻보다 먼저다.
        let supplier = try result(await pipeline().lookup(tap("supplier", in: book), book: book))
        XCTAssertEqual(supplier.source, .bookGlossary)
    }

    func testGenerationUnavailableReportsReason() async throws {
        let book = try sampleBook()
        let request = pipeline().request(for: tap("window", in: book), book: book)

        let noDevice = generation(generator: FakeGenerator(availability: .unavailable(.deviceNotEligible)))
        XCTAssertEqual(noDevice.unavailableReason, .deviceNotEligible)
        do {
            _ = try await noDevice.lookup(request)
            XCTFail("기기 미지원인데 만들었음")
        } catch let failure as WordLookupStepFailure {
            XCTAssertTrue(failure.miss.message.contains("Apple Intelligence를 지원하지 않습니다"), failure.miss.message)
        }

        let off = generation(enabled: false)
        XCTAssertEqual(off.unavailableReason, .disabledInSettings)
        do {
            _ = try await off.lookup(request)
            XCTFail("설정에서 꺼졌는데 만들었음")
        } catch let failure as WordLookupStepFailure {
            XCTAssertTrue(failure.miss.message.contains("설정"), failure.miss.message)
        }
        XCTAssertFalse(WordLookupCard.shortReason(.deviceNotEligible).isEmpty)
    }

    // MARK: - 시스템 사전 (macOS)

    func testSystemDictionaryEntryKeepsFirstSenseOnly() throws {
        let raw = "arrive ar·rive | əˈrīv | verb [no object] reach a place at the end of a journey or a stage in a journey: we arrived at his house | they had recently arrived from Turkey. • (of a thing) be brought or delivered: the invitation arrived"
        let entry = try XCTUnwrap(SystemDictionaryEntry(raw))
        XCTAssertEqual(entry.headword, "arrive")
        XCTAssertEqual(entry.partOfSpeech, "v.")
        XCTAssertEqual(entry.meaning, "reach a place at the end of a journey or a stage in a journey")

        let numbered = try XCTUnwrap(SystemDictionaryEntry("deadline dead·line | ˈdedˌlīn | noun 1 the latest time or date by which something should be completed: the deadline is … 2 historical a line"))
        XCTAssertEqual(numbered.partOfSpeech, "n.")
        XCTAssertEqual(numbered.meaning, "the latest time or date by which something should be completed")

        // 다른 모양의 사전은 앞부분만 자른다.
        let other = try XCTUnwrap(SystemDictionaryEntry(String(repeating: "도착하다 ", count: 60)))
        XCTAssertNil(other.partOfSpeech)
        XCTAssertLessThanOrEqual(other.meaning.count, SystemDictionaryEntry.maxLength + 1)
        XCTAssertNil(SystemDictionaryEntry("   "))
    }

    func testSystemDictionaryIsLastAndTriesLemmaFirst() async throws {
        let book = try sampleBook()
        let context = tap("arrived", in: book)
        let asked = AskedTerms()
        var step = SystemDictionaryLookupStep()
        step.definition = { term in
            asked.append(term)
            return term == "arrive" ? "arrive ar·rive | əˈrīv | verb reach a place: we arrived" : nil
        }
        let index = bundled
        let lookup = WordLookupPipeline(
            lemmatizer: EnglishLemmatizer(),
            steps: EnglishWordLookup.pipeline(bundledWords: { index }, wiktionary: { [:] }, generatedMeanings: meanings, usesTranslation: false, usesSystemDictionary: false).steps + [step]
        )
        let found = try result(await lookup.lookup(context, book: book))
        XCTAssertEqual(found.source, .systemDictionary)
        XCTAssertEqual(found.headword, "arrive")
        XCTAssertEqual(found.meaningForSaving, "v. reach a place")
        // 원형 후보를 본문 모양보다 먼저 묻는다.
        XCTAssertNotNil(asked.terms.firstIndex(of: "arrive"))
        XCTAssertFalse(asked.terms.contains("arrived"))

        // 책 사전에 있는 단어는 시스템 사전까지 가지 않는다.
        asked.terms.removeAll()
        _ = try result(await lookup.lookup(tap("allocated", in: book), book: book))
        XCTAssertTrue(asked.terms.isEmpty)
    }

    #if os(macOS)
    func testRealMacDictionaryFindsBasicWord() async throws {
        guard let raw = SystemDictionaryLookupStep.systemDefinition("arrive") else {
            throw XCTSkip("이 Mac에 기본 사전이 없음")
        }
        XCTAssertNotNil(SystemDictionaryEntry(raw))
        let book = try sampleBook()
        let found = try result(await EnglishWordLookup.pipeline(wiktionary: { [:] }, generatedMeanings: meanings, usesTranslation: false).lookup(tap("arrived", in: book), book: book))
        XCTAssertEqual(found.source, .systemDictionary)
        XCTAssertFalse(found.meaning.isEmpty)
    }
    #endif

    private final class AskedTerms: @unchecked Sendable {
        var terms: [String] = []
        func append(_ term: String) { terms.append(term) }
    }

    func testAskPromptCarriesWordAndSentence() throws {
        let book = try sampleBook()
        let context = tap("allocated", in: book)
        let prompt = WordAskPrompt(context)
        XCTAssertTrue(prompt.text.contains("단어: allocated"))
        XCTAssertTrue(prompt.text.contains("문장: \(context.sentence)"))
        if let translation = context.sentenceTranslation {
            XCTAssertTrue(prompt.text.contains("문장 번역: \(translation)"))
        }

        for destination in WordAskPrompt.Destination.allCases {
            let url = try XCTUnwrap(prompt.url(for: destination))
            let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value)
            XCTAssertEqual(query, prompt.text)
        }
        XCTAssertEqual(prompt.url(for: .chatGPT)?.host(), "chatgpt.com")
        XCTAssertEqual(prompt.url(for: .claude)?.host(), "claude.ai")

        // `+`·`&`가 있어도 원문 그대로 돌아온다.
        let tricky = WordAskPrompt(surface: "R&D", sentence: "1 + 1 & more", sentenceTranslation: nil)
        let url = try XCTUnwrap(tricky.url(for: .claude))
        XCTAssertFalse(url.absoluteString.contains("+"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        XCTAssertEqual(query, tricky.text)
        XCTAssertEqual(SystemDictionary.url(for: "allocate")?.absoluteString, "dict://allocate")
    }

    func testLemmatizerNormalizesTappedSurface() {
        let lemmatizer = EnglishLemmatizer()
        XCTAssertEqual(lemmatizer.normalize("Friday,"), "friday")
        XCTAssertEqual(lemmatizer.normalize("manager's"), "manager")
        XCTAssertEqual(lemmatizer.normalize("“Deadlines”"), "deadlines")
        XCTAssertEqual(lemmatizer.lemmas(of: "allocated", in: "Her manager had already allocated a desk near the window for her.").first, "allocate")
        XCTAssertEqual(lemmatizer.lemmas(of: "contracts", in: "Mina had finished reviewing all twelve contracts.").first, "contract")
        XCTAssertTrue(lemmatizer.lemmas(of: "reviewing", in: "Mina had finished reviewing all twelve contracts.").contains("review"))
    }

    /// lemma 모델이 없는 환경에서 쓰는 규칙 후보.
    func testRuleLemmasUndoRegularInflections() {
        XCTAssertTrue(EnglishLemmatizer.ruleLemmas(of: "allocated").starts(with: ["allocate"]))
        XCTAssertTrue(EnglishLemmatizer.ruleLemmas(of: "planned").contains("plan"))
        XCTAssertTrue(EnglishLemmatizer.ruleLemmas(of: "running").contains("run"))
        XCTAssertTrue(EnglishLemmatizer.ruleLemmas(of: "companies").contains("company"))
        XCTAssertTrue(EnglishLemmatizer.ruleLemmas(of: "deadlines").contains("deadline"))
        XCTAssertFalse(EnglishLemmatizer.ruleLemmas(of: "business").contains("busines"))
        XCTAssertEqual(EnglishLemmatizer.ruleLemmas(of: "was"), [])
    }

    // MARK: - 단어 추가

    func testDraftUsesTappedSentenceAndPassesWordDataCheck() async throws {
        let book = try sampleBook()
        let context = tap("allocated", in: book)
        let found = try result(await pipeline().lookup(context, book: book))
        let draft = ReaderWordSaver.draft(for: found, context: context, book: book)

        XCTAssertEqual(draft.english, "allocate")
        XCTAssertEqual(draft.meaningKo, "v. 할당하다, 배정하다")
        XCTAssertEqual(draft.exampleEn, "Her manager had already allocated a desk near the window for her.")
        XCTAssertEqual(draft.exampleKo, "그녀의 매니저는 이미 창가 근처 책상을 그녀에게 배정해 두었다.")
        XCTAssertEqual(draft.toeicTag, "책 · The First Week")
        XCTAssertEqual(ReaderWordSaver.issues(for: draft), [])
        XCTAssertTrue(WordDataCheck.isQuizReady(ReaderWordSaver.issues(for: draft)))

        // 번역이 없는 문장이면 권장 항목만 빠진다.
        var untranslated = context
        untranslated.sentenceTranslation = nil
        let bare = ReaderWordSaver.draft(for: found, context: untranslated, book: book)
        XCTAssertEqual(ReaderWordSaver.issues(for: bare), [.missingExampleTranslation])
    }

    func testAddPutsWordInCollectionDayWithoutTouchingSchedule() throws {
        let container = try ModelContainer(for: VocabularyDay.self, VocaWord.self, configurations: .init(isStoredInMemoryOnly: true))
        let modelContext = container.mainContext
        let existing = DayFactory.createDay(title: "데이 1", in: modelContext)

        let first = VocaWordJSON(english: "allocate", meaningKo: "v. 할당하다", exampleEn: "She allocated a desk.", exampleKo: "그녀는 책상을 배정했다.")
        let day = try ReaderWordSaver.add(first, existingDays: [existing], in: modelContext)
        XCTAssertEqual(day.title, ReaderWordSaver.dayTitle)
        XCTAssertEqual(day.source, ReaderWordSaver.daySource)
        let word = try XCTUnwrap(day.wordList.first)
        XCTAssertEqual(word.exampleEn, "She allocated a desk.")
        XCTAssertEqual(word.srsStage, 0)
        XCTAssertEqual(word.srsNextLearningDay, 0)
        XCTAssertEqual(word.srsIdkCount, 0)

        // 두 번째 단어도 같은 데이에 모인다.
        let second = VocaWordJSON(english: "supplier", meaningKo: "n. 공급업체", exampleEn: "The supplier called.", exampleKo: "공급업체가 전화했다.")
        let again = try ReaderWordSaver.add(second, existingDays: [existing, day], in: modelContext)
        XCTAssertEqual(again.id, day.id)
        XCTAssertEqual(again.wordList.count, 2)
        let days = try modelContext.fetch(FetchDescriptor<VocabularyDay>())
        XCTAssertEqual(days.count, 2)
    }

    func testAddRejectsDuplicatesFromAnyDay() throws {
        let container = try ModelContainer(for: VocabularyDay.self, VocaWord.self, configurations: .init(isStoredInMemoryOnly: true))
        let modelContext = container.mainContext
        let day1 = DayFactory.createDay(title: "데이 1", in: modelContext)
        let owned = GeneratedWordDraftMapper.makeEntity(from: VocaWordJSON(english: "Deadline", meaningKo: "n. 마감일"), day: day1)
        modelContext.insert(owned)
        day1.appendWord(owned)

        XCTAssertEqual(ReaderWordSaver.existingDayTitle(for: " deadline ", in: [day1]), "데이 1")
        let draft = VocaWordJSON(english: "deadline", meaningKo: "n. 마감일", exampleEn: "She marked every deadline.")
        XCTAssertThrowsError(try ReaderWordSaver.add(draft, existingDays: [day1], in: modelContext)) { error in
            XCTAssertEqual(error as? ReaderWordSaveError, .duplicate(dayTitle: "데이 1"))
        }

        // 리더에서 넣은 단어를 다시 넣어도 막는다.
        let added = try ReaderWordSaver.add(VocaWordJSON(english: "allocate", meaningKo: "v. 할당하다"), existingDays: [day1], in: modelContext)
        XCTAssertThrowsError(try ReaderWordSaver.add(VocaWordJSON(english: "Allocate", meaningKo: "v. 할당하다"), existingDays: [day1, added], in: modelContext))
        XCTAssertEqual(added.wordList.count, 1)
    }

    func testAddRefusesWordWithoutMeaning() throws {
        let container = try ModelContainer(for: VocabularyDay.self, VocaWord.self, configurations: .init(isStoredInMemoryOnly: true))
        XCTAssertThrowsError(try ReaderWordSaver.add(VocaWordJSON(english: "window"), existingDays: [], in: container.mainContext)) { error in
            XCTAssertEqual(error as? ReaderWordSaveError, .notSavable(.missingMeaning))
        }
    }

    func testHighlighterMatchesWholeWordOnly() {
        let sentence = "Preview the review before you review it."
        let range = WordHighlighter.range(of: "review", in: sentence)
        XCTAssertEqual(range.map { String(sentence[$0]) }, "review")
        XCTAssertEqual(range.map { sentence.distance(from: sentence.startIndex, to: $0.lowerBound) }, 12)
        XCTAssertNil(WordHighlighter.range(of: "view", in: sentence))
    }

    // MARK: - 발음

    /// 단어 하나를 Kokoro로 만든다. 모델 파일이 없거나 시뮬레이터면 건너뛴다 (그때 카드는 시스템 음성으로 읽는다).
    func testKokoroSpeaksSingleWord() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX는 시뮬레이터에서 동작하지 않는다.")
        #else
        guard Bundle.main.url(forResource: "kokoro-v1_0", withExtension: "safetensors") != nil else {
            throw XCTSkip("Kokoro 모델 파일이 없다.")
        }
        let samples = try await KokoroSynthesizer.shared.generate(
            "allocate",
            voice: ListeningVoice.fallback,
            speed: WordPronunciationPlayer.speed
        )
        let seconds = Double(samples.count) / KokoroSynthesizer.sampleRate
        XCTAssertGreaterThan(seconds, 0.3)
        XCTAssertLessThan(seconds, 3.0)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.01)
        #endif
    }

    // MARK: - 뜻 상자

    func testMeaningLinesPutSinglePartOfSpeechNextToWord() {
        func lines(_ meaning: String, pos: String? = nil) -> MeaningLines {
            MeaningLines(WordLookupResult(headword: "w", surface: "w", partOfSpeech: pos, meaning: meaning, source: .bundledPack))
        }
        XCTAssertEqual(lines("할당하다, 배정하다", pos: "v."), MeaningLines(partOfSpeech: "v.", lines: ["할당하다, 배정하다"]))
        XCTAssertEqual(lines("n. 계약, 계약서"), MeaningLines(partOfSpeech: "n.", lines: ["계약, 계약서"]))
        XCTAssertEqual(lines("n. 검토, 평가 / v. 검토하다, 평가하다"), MeaningLines(partOfSpeech: nil, lines: ["n. 검토, 평가", "v. 검토하다, 평가하다"]))
        XCTAssertEqual(lines("v. 달리다, v. 운영하다, n. 달리기, adj. 빠른"), MeaningLines(partOfSpeech: nil, lines: ["v. 달리다", "v. 운영하다", "n. 달리기"]))
        XCTAssertEqual(lines("뜻만 있음"), MeaningLines(partOfSpeech: nil, lines: ["뜻만 있음"]))
    }

    func testShortNoticeOnlyForProblemsThatMatter() {
        XCTAssertNotNil(WordLookupCard.shortNotice(.missingMeaning))
        XCTAssertNotNil(WordLookupCard.shortNotice(.exampleMissingWord))
        XCTAssertNil(WordLookupCard.shortNotice(.missingExampleTranslation))
    }

    // MARK: - 카드 캡처

    /// 샘플 책 단어로 뜻 상자를 그려 결과 번들에 첨부한다 (보고용 캡처, 팝오버 폭 300pt).
    func testRenderCardCaptures() async throws {
        let book = try sampleBook()
        let container = try ModelContainer(for: VocabularyDay.self, VocaWord.self, configurations: .init(isStoredInMemoryOnly: true))
        try ReaderWordSaver.add(
            VocaWordJSON(english: "deadline", meaningKo: "n. 마감일, 기한", exampleEn: "She took careful notes and marked every deadline."),
            existingDays: [],
            in: container.mainContext
        )

        let cases: [(surface: String, name: String, fixed: WordLookupCard.Phase?, scheme: ColorScheme)] = [
            ("allocated", "found", nil, .light),
            ("allocated", "found-dark", nil, .dark),
            ("reviewing", "found-multi", nil, .light),
            ("deadline", "saved", nil, .light),
            ("Mina", "not-found", .notFound(WordLookupMiss(message: "책 사전과 기본 단어장에 없는 단어예요.")), .light),
        ]
        var index = bundled
        index["review"] = VocaWordJSON(english: "review", meaningKo: "n. 검토, 평가 / v. 검토하다, 평가하다")
        let words = index
        var book2 = book
        book2.glossary.removeAll { $0.lemma == "review" }
        let lookup = EnglishWordLookup.pipeline(bundledWords: { words }, generatedMeanings: emptyMeaningStore(), usesTranslation: false, usesSystemDictionary: false)
        for item in cases {
            let context = tap(item.surface, in: book2)
            let phase: WordLookupCard.Phase
            if let fixed = item.fixed {
                phase = fixed
            } else {
                switch await lookup.lookup(context, book: book2) {
                case .found(let found): phase = .found(found)
                case .notFound(let miss): phase = .notFound(miss)
                }
            }
            let card = WordLookupCard(context: context, book: book2, pipeline: lookup, initialPhase: phase)
                .modelContainer(container)
                .frame(width: 300)
                .background(item.scheme == .dark ? Color.black : AppTheme.background)
                .environment(\.colorScheme, item.scheme)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            #if os(macOS)
            let platform = "mac"
            let data = try XCTUnwrap(renderer.nsImage?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
            #else
            let platform = "iphone"
            let data = try XCTUnwrap(renderer.uiImage?.pngData())
            #endif
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "card-v2-\(platform)-\(item.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
