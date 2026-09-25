import XCTest
@testable import VocaDay

final class SessionPlannerTests: XCTestCase {
    private func config(_ modes: Set<ExamItemKind>) -> SessionPlannerConfig {
        var config = SessionPlannerConfig.standard
        config.enabledModes = modes
        return config
    }

    private func words(_ plan: ExamPlan, _ kind: ExamItemKind) -> [UUID] {
        plan.items.filter { $0.kind == kind }.flatMap(\.wordIDs)
    }

    // MARK: 유형 배정 (가중 무작위)

    func testAllTypesAppearWithRichData() {
        let words = ExamFixtures.localPastVerbs { $0 % 8 }
        var kinds: Set<ExamItemKind> = []
        for day in 0..<12 {
            let plan = SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: day)
            kinds.formUnion(plan.items.map(\.kind))
            XCTAssertEqual(plan.gradedCount, words.count, "단어 하나당 채점 문제 1개")
        }
        XCTAssertEqual(kinds, [.match, .meaningChoice, .choice, .letterTiles, .clozeTyping, .koToEn, .dictation])
    }

    func testModeSelectionIsDeterministic() {
        let words = ExamFixtures.localPastVerbs()
        let first = SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: 3)
        let second = SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: 3)
        XCTAssertEqual(first, second)
    }

    func testHigherStagesFavorRecall() {
        let low = ExamFixtures.localPastVerbs { _ in 0 }
        let high = ExamFixtures.localPastVerbs { _ in 8 }
        func count(_ words: [QuizWord], _ kind: ExamItemKind) -> Int {
            (0..<8).reduce(0) { total, day in
                total + SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: day).items
                    .filter { $0.kind == kind }.flatMap(\.wordIDs).count
            }
        }
        XCTAssertGreaterThan(count(high, .clozeTyping), count(low, .clozeTyping))
        XCTAssertGreaterThan(count(low, .match), count(high, .match))
    }

    func testNewWordsAreNeverAskedToTypeSpelling() {
        let words = ExamFixtures.localPastVerbs { $0 % 2 }
        for day in 0..<10 {
            let plan = SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: day)
            let recall: Set<ExamItemKind> = [.letterTiles, .clozeTyping, .koToEn, .dictation]
            XCTAssertTrue(Set(plan.items.map(\.kind)).isDisjoint(with: recall), "stage 0·1 은 알아보기 유형만")
        }
    }

    func testWordsWithoutUsableExampleSkipClozeTypes() {
        let words = (0..<12).map { ExamFixtures.plain("word\($0)", meaning: "뜻\($0)", stage: $0 % 8, idk: 1) }
        let plan = SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: 2)
        XCTAssertTrue(Set(plan.items.map(\.kind)).isSubset(of: [.match, .meaningChoice, .koToEn]), "\(plan.items.map(\.kind))")
        XCTAssertEqual(plan.gradedCount, 12)
    }

    func testNewWordCardsOnlyWhenEnabled() {
        let words = (0..<6).map { ExamFixtures.plain("word\($0)", meaning: "뜻\($0)") }
        XCTAssertFalse(SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: 0).items.contains { $0.kind == .newWord })

        var config = SessionPlannerConfig.standard
        config.introducesNewWords = true
        let introduced = SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: 0, config: config)
        XCTAssertEqual(Set(self.words(introduced, .newWord)), Set(words.map(\.id)))
        let retry = SessionPlanner.plan(targets: words, allWords: words, kind: .retry, learningDay: 0, config: config)
        XCTAssertFalse(retry.items.contains { $0.kind == .newWord })
    }

    func testTooFewWordsFallBackToTyping() {
        let words = (0..<2).map { ExamFixtures.plain("word\($0)", meaning: "뜻\($0)") }
        let plan = SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: 0)
        XCTAssertEqual(Set(self.words(plan, .koToEn)), Set(words.map(\.id)))
    }

    func testIdiomNeverUsesChoice() {
        var idiom = ExamFixtures.verb("once in a blue moon", past: "", ing: "", third: "", meaning: "아주 드물게", pos: "idiom", clozeForm: "base")
        idiom.forms = ["base": "once in a blue moon"]
        let all = ExamFixtures.pastVerbs + [idiom]
        for day in 0..<10 {
            let plan = SessionPlanner.plan(targets: [idiom], allWords: all, kind: .first, learningDay: day)
            XCTAssertFalse(plan.items.contains { $0.kind == .choice })
        }
    }

    func testChoiceFallsBackWhenDistractorsMissing() {
        let lonely = ExamFixtures.verb("abandon", past: "abandoned", ing: "abandoning", third: "abandons", meaning: "버리다")
        let plan = SessionPlanner.plan(targets: [lonely], allWords: [lonely] + ExamFixtures.pastVerbs.prefix(2), kind: .first, learningDay: 0, config: config([.choice]))
        XCTAssertEqual(plan.items.map(\.kind), [.clozeTyping])
    }

    // MARK: 빈칸 고르기 보기 (5지선다)

    func testClozeChoiceHasFiveOptionsInSameInflection() throws {
        let words = ExamFixtures.pastVerbs
        let plan = SessionPlanner.plan(targets: [words[0]], allWords: words, kind: .first, learningDay: 0, config: config([.choice]))
        let item = try XCTUnwrap(plan.items.first { $0.kind == .choice })

        XCTAssertEqual(item.options.count, 5)
        XCTAssertTrue(item.options.contains("gave up"))
        let userPastForms = Set(words.filter { $0.pos == "phrasal_verb" }.map { $0.form("past") })
        XCTAssertTrue(Set(item.options).isSubset(of: userPastForms), "보기는 사용자 단어의 같은 활용형(과거형)만")
    }

    func testLocalClozeChoiceUsesOtherExamplesAnswers() throws {
        let words = ExamFixtures.localPastVerbs()
        let target = words[0]
        XCTAssertEqual(target.clozeAnswer, "postponed")
        let plan = SessionPlanner.plan(targets: [target], allWords: words, kind: .first, learningDay: 0, config: config([.choice]))
        let item = try XCTUnwrap(plan.items.first)
        XCTAssertEqual(item.kind, .choice)
        XCTAssertEqual(item.options.count, 5)
        XCTAssertTrue(item.options.allSatisfy { $0.hasSuffix("ed") }, "\(item.options)")
    }

    func testDistractorsExcludeNearMissAndSameMeaning() {
        var words = ExamFixtures.pastVerbs
        words.append(ExamFixtures.verb("quit", past: "quit", ing: "quitting", third: "quits", meaning: "그만두다", pos: "phrasal_verb"))
        words.append(ExamFixtures.verb("give in", past: "gave in", pp: "given in", ing: "giving in", third: "gives in", meaning: "포기하다", pos: "phrasal_verb"))
        let pool = SessionPlanner.clozeDistractorPool(for: words[0], index: .init(words)).map(\.word.term)
        XCTAssertFalse(pool.contains("quit"))
        XCTAssertFalse(pool.contains("give in"))
        XCTAssertFalse(pool.contains("abandon"), "품사가 다르면 제외")
    }

    // MARK: 뜻 고르기 (5지선다)

    func testMeaningChoiceHasFiveDistinctMeanings() throws {
        let words = [
            ExamFixtures.plain("result", meaning: "결과"),
            ExamFixtures.plain("outcome", meaning: "결과, 성과"),
            ExamFixtures.plain("river", meaning: "강"),
            ExamFixtures.plain("shore", meaning: "해안"),
            ExamFixtures.plain("decide", meaning: "결정하다"),
            ExamFixtures.plain("hire", meaning: "고용하다"),
            ExamFixtures.plain("cancel", meaning: "취소하다"),
        ]
        let plan = SessionPlanner.plan(targets: [words[0]], allWords: words, kind: .first, learningDay: 0, config: config([.meaningChoice]))
        let item = try XCTUnwrap(plan.items.first)
        XCTAssertEqual(item.kind, .meaningChoice)
        XCTAssertEqual(item.options.count, 5)
        XCTAssertTrue(item.options.contains("결과"))
        XCTAssertFalse(item.options.contains("결과, 성과"), "뜻이 겹치는 보기는 정답이 둘이 되므로 제외")
        XCTAssertEqual(Set(item.options).count, 5)
    }

    // MARK: M1

    func testMatchScreensNeverShowOverlappingMeanings() {
        let words = [
            ExamFixtures.plain("result", meaning: "결과"),
            ExamFixtures.plain("consequence", meaning: "결과"),
            ExamFixtures.plain("outcome", meaning: "결과, 성과"),
            ExamFixtures.plain("decide", meaning: "결정하다"),
            ExamFixtures.plain("determine", meaning: "결정한"),
            ExamFixtures.plain("river", meaning: "강"),
            ExamFixtures.plain("bank", meaning: "둑 (강가)"),
            ExamFixtures.plain("shore", meaning: "해안"),
        ]
        let plan = SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: 0, config: config([.match]))
        let byID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        for item in plan.items where item.kind == .match {
            let screen = (item.wordIDs + item.fillerWordIDs).compactMap { byID[$0] }
            XCTAssertGreaterThanOrEqual(screen.count, 3)
            XCTAssertLessThanOrEqual(screen.count, 5)
            for (i, lhs) in screen.enumerated() {
                for rhs in screen[(i + 1)...] {
                    XCTAssertFalse(lhs.meaningsOverlap(with: rhs), "\(lhs.term) / \(rhs.term)")
                }
            }
        }
        XCTAssertEqual(Set(plan.gradedWordIDs), Set(words.map(\.id)))
    }

    func testMatchFillersComeFromNonTargetsFirstAndAreNotGraded() throws {
        let target = ExamFixtures.plain("abandon", meaning: "버리다")
        let others = (0..<6).map { ExamFixtures.plain("other\($0)", meaning: "다른 뜻\($0)", stage: 4, idk: 0, next: 9) }
        let plan = SessionPlanner.plan(targets: [target], allWords: [target] + others, kind: .first, learningDay: 0, config: config([.match]))
        let match = try XCTUnwrap(plan.items.first { $0.kind == .match })
        XCTAssertEqual(match.wordIDs, [target.id])
        XCTAssertEqual(match.fillerWordIDs.count, 4)
        XCTAssertTrue(Set(match.fillerWordIDs).isSubset(of: Set(others.map(\.id))))
        XCTAssertEqual(plan.gradedCount, 1)
    }

    func testMeaningNormalization() {
        XCTAssertEqual(ExamText.normalizeMeaning("결정하다"), "결정")
        XCTAssertEqual(ExamText.normalizeMeaning("결정한"), "결정")
        XCTAssertEqual(ExamText.normalizeMeaning("둑 (강가)"), "둑")
        XCTAssertEqual(ExamText.normalizeMeaning("조용히"), "조용")
        XCTAssertEqual(ExamText.meaningKeys("결과, 성과; 산물"), ["결과", "성과", "산물"])
    }

    // MARK: 순서·레슨

    func testNoTripleSameKindWhenAvoidable() {
        let kinds: [ExamItemKind] = Array(repeating: .clozeTyping, count: 6) + Array(repeating: .choice, count: 5) + Array(repeating: .meaningChoice, count: 2)
        let arranged = SessionPlanner.arrangeAvoidingTriples(kinds) { $0 }
        XCTAssertEqual(arranged.count, kinds.count)
        for index in 2..<arranged.count {
            XCTAssertFalse(arranged[index] == arranged[index - 1] && arranged[index] == arranged[index - 2], "같은 유형 3연속: \(arranged)")
        }
    }

    func testLessonsSplitEveryFifteenGradedQuestions() {
        let words = (0..<40).map { ExamFixtures.plain("w\($0)", meaning: "뜻\($0)", stage: 7, idk: 1) }
        let plan = SessionPlanner.plan(targets: words, allWords: words, kind: .first, learningDay: 0, config: config([.meaningChoice]))
        XCTAssertEqual(plan.lessonBreaksAfter, [14, 29])
    }

    // MARK: 오답 다시 풀기

    func testReplayReusesOriginalKinds() {
        let words = ExamFixtures.pastVerbs
        let plan = SessionPlanner.plan(targets: [words[0]], allWords: words, kind: .first, learningDay: 0, config: config([.choice]))
        let replay = SessionPlanner.replayItems(wrongWordIDs: [words[0].id], originalPlan: plan, allWords: words, round: 1)
        XCTAssertEqual(replay.map(\.kind), [.choice])
        XCTAssertEqual(replay.first?.options, plan.items.first?.options)
    }

    // MARK: 떠올리기 유형

    func testLetterTilesContainAnswerLettersPlusDecoys() throws {
        let words = ExamFixtures.localPastVerbs { _ in 2 }
        let plan = SessionPlanner.plan(targets: [words[0]], allWords: words, kind: .first, learningDay: 0, config: config([.letterTiles]))
        let item = try XCTUnwrap(plan.items.first)
        XCTAssertEqual(item.kind, .letterTiles)
        XCTAssertEqual(item.options.count, "postpone".count + SessionPlanner.letterTileDecoyCount)
        XCTAssertEqual(item.options.filter { !"postpone".contains($0) }.count, SessionPlanner.letterTileDecoyCount)
        XCTAssertEqual(item.options, SessionPlanner.plan(targets: [words[0]], allWords: words, kind: .first, learningDay: 0, config: config([.letterTiles])).items.first?.options, "같은 날은 같은 배치")
    }

    func testPhraseTilesSkipSpaces() {
        let phrase = ExamFixtures.local("give up", meaning: "v. 포기하다", example: "She gave up smoking.", stage: 2)
        let tiles = SessionPlanner.letterTiles(for: phrase, seed: "s")
        XCTAssertFalse(tiles.contains(" "))
        XCTAssertEqual(tiles.count, 6 + SessionPlanner.letterTileDecoyCount)
    }

    func testRecallModesUnlockByStage() {
        let index = SessionPlanner.WordIndex(ExamFixtures.localPastVerbs())
        func modes(_ stage: Int) -> [ExamItemKind] {
            var word = ExamFixtures.localPastVerbs()[0]
            word.card.stage = stage
            return SessionPlanner.availableModes(for: word, index: index, config: .standard)
        }
        XCTAssertFalse(modes(1).contains(.letterTiles))
        XCTAssertTrue(modes(2).contains(.letterTiles))
        XCTAssertTrue(modes(2).contains(.koToEn))
        XCTAssertFalse(modes(2).contains(.dictation))
        XCTAssertTrue(modes(3).contains(.dictation))
    }

    func testKoToEnHintFadesWithStage() throws {
        var word = ExamFixtures.localPastVerbs()[0]
        let words = ExamFixtures.localPastVerbs()
        word.card.stage = 3
        let early = try XCTUnwrap(SessionPlanner.plan(targets: [word], allWords: words, kind: .first, learningDay: 0, config: config([.koToEn])).items.first)
        XCTAssertEqual(early.kind, .koToEn)
        XCTAssertEqual(early.hint, .firstLetters)
        word.card.stage = 7
        let late = try XCTUnwrap(SessionPlanner.plan(targets: [word], allWords: words, kind: .first, learningDay: 0, config: config([.koToEn])).items.first)
        XCTAssertEqual(late.hint, ClozeHint.none)
    }

    func testReplayCoversWordsMissedOnFlashcards() {
        let words = (0..<6).map { ExamFixtures.plain("word\($0)", meaning: "뜻\($0)") }
        let replay = SessionPlanner.replayItems(wrongWordIDs: [words[0].id], originalPlan: .empty, allWords: words, round: 1)
        XCTAssertEqual(replay.flatMap(\.gradedWordIDs), [words[0].id])
    }
}
