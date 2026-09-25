import Foundation

nonisolated struct SessionPlannerConfig: Equatable, Sendable {
    var lessonSize = 15
    var matchPairsPerScreen = 5
    var minimumMatchPairs = 3
    /// 이 수보다 적으면 M1에 채움 단어를 넣는다 (SPEC §4 M1).
    var matchFillThreshold = 4
    /// 5지선다: 정답 1 + 오답 4.
    var choiceDistractorCount = 4
    var choiceCandidatePoolSize = 8
    var recentOptionWindow = 5
    /// 처음 보는 단어 앞에 "새 단어 카드"(채점 X)를 넣을지. 기본은 끔 — 복습 카드가 첫 노출 역할을 한다.
    var introducesNewWords = false
    /// 무작위로 섞을 유형. 기본은 네 가지 모두.
    var enabledModes: Set<ExamItemKind> = Set(SessionPlanner.randomModes)

    static let standard = SessionPlannerConfig()
}

/// 오늘 대상 → 유형 배정 → M1 묶기 → 순서 → 보기 생성 → 레슨 분할 (SPEC §3, §4). UI와 저장소에 의존하지 않는다.
///
/// 유형은 네 가지(짝 맞추기·빈칸 고르기·빈칸 쓰기·뜻 고르기)를 **가중 무작위**로 섞는다.
/// 단계(stage)가 오를수록 알아보기(고르기)보다 떠올리기(쓰기) 비중을 높인다 — 인출 연습은
/// 어려울수록 기억에 오래 남는다(바람직한 어려움). 같은 단어·학습일이면 같은 유형이 나오도록 결정적 난수를 쓴다.
nonisolated enum SessionPlanner {
    /// 보강 데이터상 빈칸 고르기를 쓰지 않는 품사 (SPEC §4 M2).
    static let choiceExcludedPOS: Set<String> = ["idiom", "preposition", "conjunction", "other"]
    /// 무작위로 섞는 유형. (M4 한→영 쓰기는 다른 유형이 모두 불가능할 때만 쓴다.)
    /// (M6 "번역 없는 빈칸 고르기"는 M2가 해석을 기본으로 가리게 되면서 M2에 합쳤다. 예전 저장본을 위해 enum만 남긴다.)
    static let randomModes: [ExamItemKind] = [.match, .meaningChoice, .choice, .letterTiles, .clozeTyping, .koToEn, .dictation]
    /// 빈칸 쓰기는 철자까지 맞혀야 해서 어렵다. 알아보기로 두 번 이상 맞힌 단어(stage ≥ 2)부터 낸다.
    static let minimumTypingStage = 2
    /// 글자 조각에 섞는 가짜 글자 수.
    static let letterTileDecoyCount = 2
    private static let cefrOrder = ["A1", "A2", "B1", "B2", "C1", "C2"]

    // MARK: 계획

    static func plan(
        targets: [QuizWord],
        allWords: [QuizWord],
        kind: SRSSessionKind,
        learningDay: Int,
        config: SessionPlannerConfig = .standard
    ) -> ExamPlan {
        guard !targets.isEmpty else { return .empty }
        let seed = "\(kind.rawValue)|\(learningDay)"
        let targetIDs = Set(targets.map(\.id))
        let index = WordIndex(allWords)

        // 1) 가능한 유형 중 가중 무작위
        var matchWords: [QuizWord] = []
        var singles: [(word: QuizWord, kind: ExamItemKind)] = []
        for word in targets {
            let mode = pickMode(for: word, index: index, seed: seed, config: config)
            if mode == .match {
                matchWords.append(word)
            } else {
                singles.append((word, mode))
            }
        }

        // 2) M1 화면 묶기 (채점 대상끼리 뜻이 겹치지 않게, 부족하면 채움 단어)
        let (matchGroups, unplaceable) = buildMatchGroups(
            matchWords,
            allWords: allWords,
            excludedFromFillers: targetIDs,
            seed: seed,
            config: config
        )
        for word in unplaceable {
            singles.append((word, fallbackMode(for: word, excluding: .match, index: index, config: config)))
        }

        let introduce: (QuizWord) -> Bool = { config.introducesNewWords && kind == .first && $0.card.isNeverGraded }

        // 3) 순서: M1 묶음 먼저(워밍업), 나머지는 섞되 같은 유형 3연속 금지
        var items: [ExamPlanItem] = []
        for group in matchGroups {
            for id in group.graded where index.byID[id].map(introduce) ?? false {
                items.append(ExamPlanItem(kind: .newWord, wordIDs: [id]))
            }
            items.append(ExamPlanItem(kind: .match, wordIDs: group.graded, fillerWordIDs: group.fillers))
        }

        var generator = SeededGenerator(seed, "order")
        let ordered = arrangeAvoidingTriples(singles.shuffled(using: &generator), kindOf: { $0.kind })

        // 4) 보기는 순서가 정해진 뒤 "최근 5문제" 감점을 반영해 만든다.
        var recentOptionTerms: [[String]] = []
        for single in ordered {
            let word = single.word
            if introduce(word) {
                items.append(ExamPlanItem(kind: .newWord, wordIDs: [word.id]))
            }
            let recent = Set(recentOptionTerms.suffix(config.recentOptionWindow).flatMap { $0 })

            // 배정한 유형의 보기를 못 만들면 떠올리기 쪽(쓰기 → 빈칸 고르기 → 뜻 고르기) 순서로 대체한다.
            let order = [single.kind] + [ExamItemKind.choice, .meaningChoice, .clozeTyping].filter { $0 != single.kind }
            var resolved: (kind: ExamItemKind, options: [String], usedTerms: [String])?
            for mode in order where resolved == nil {
                switch mode {
                case .choice, .clozeChoiceWithoutTranslation:
                    let picked = clozeDistractors(for: word, index: index, recentlyUsed: recent, seed: seed, config: config)
                    if picked.count >= config.choiceDistractorCount {
                        let options = choiceOptions(answer: word.clozeAnswer, distractors: picked.map(\.rendered), word: word, seed: seed)
                        resolved = (mode, options, picked.map { index.normalizedTerm($0.word) })
                    }
                case .meaningChoice:
                    let picked = meaningDistractors(for: word, index: index, recentlyUsed: recent, seed: seed, config: config)
                    if picked.count >= config.choiceDistractorCount {
                        var optionGenerator = SeededGenerator(seed, word.id.uuidString, "meaning-options")
                        let options = ([word.meaningKo] + picked.map(\.meaningKo)).shuffled(using: &optionGenerator)
                        resolved = (.meaningChoice, options, picked.map { index.normalizedTerm($0) })
                    }
                case .clozeTyping:
                    // 대체 단계에서도 쓰기는 마지막 수단: 고르기가 모두 불가능할 때만.
                    if word.hasCloze { resolved = (.clozeTyping, [], []) }
                case .letterTiles:
                    if canUseLetterTiles(word) { resolved = (.letterTiles, letterTiles(for: word, seed: seed), []) }
                case .koToEn, .dictation:
                    resolved = (mode, [], [])
                default:
                    break
                }
            }
            let item = resolved ?? (.koToEn, [], [])
            recentOptionTerms.append(item.usedTerms)
            items.append(ExamPlanItem(
                kind: item.kind,
                wordIDs: [word.id],
                options: item.options,
                hint: [.clozeTyping, .koToEn].contains(item.kind) ? hint(forStage: word.card.stage) : nil
            ))
        }

        return ExamPlan(items: items, lessonBreaksAfter: lessonBreaks(for: items, lessonSize: config.lessonSize))
    }

    // MARK: 유형 배정

    /// 단계별 가중치. 낮은 단계는 알아보기(짝·뜻·빈칸 고르기), 올라갈수록 떠올리기 비중이 커진다.
    /// 떠올리기 사다리: 글자 조각(stage 2~) → 빈칸 쓰기·한→영 쓰기(힌트) → 한→영(힌트 없음)·받아쓰기(stage 6~).
    static func modeWeights(stage: Int) -> [ExamItemKind: Double] {
        switch stage {
        case ...0: [.match: 3, .meaningChoice: 3, .choice: 2]
        case 1: [.match: 2, .meaningChoice: 2, .choice: 3]
        case 2: [.match: 1.5, .meaningChoice: 2, .choice: 2.5, .letterTiles: 3, .clozeTyping: 1, .koToEn: 0.5]
        case 3...5: [.match: 1, .meaningChoice: 1.5, .choice: 2, .letterTiles: 1.5, .clozeTyping: 3, .koToEn: 2, .dictation: 0.5]
        default: [.match: 0.5, .meaningChoice: 1, .choice: 1.5, .letterTiles: 0.5, .clozeTyping: 3, .koToEn: 3, .dictation: 2.5]
        }
    }

    /// 이 단어에 지금 데이터로 낼 수 있는 유형들.
    static func availableModes(for word: QuizWord, allWords: [QuizWord], config: SessionPlannerConfig = .standard) -> [ExamItemKind] {
        availableModes(for: word, index: WordIndex(allWords), config: config)
    }

    static func availableModes(for word: QuizWord, index: WordIndex, config: SessionPlannerConfig) -> [ExamItemKind] {
        randomModes.filter { mode in
            guard config.enabledModes.contains(mode) else { return false }
            return switch mode {
            case .match:
                !word.meaningKo.isEmpty && index.words.filter { !$0.meaningKo.isEmpty }.count >= config.minimumMatchPairs
            case .meaningChoice:
                !word.meaningKo.isEmpty && meaningDistractorPool(for: word, index: index, limit: config.choiceDistractorCount).count >= config.choiceDistractorCount
            case .choice, .clozeChoiceWithoutTranslation:
                canUseChoice(word) && clozeDistractorPool(for: word, index: index, limit: config.choiceDistractorCount).count >= config.choiceDistractorCount
            case .clozeTyping:
                word.hasCloze && word.card.stage >= minimumTypingStage
            case .letterTiles:
                canUseLetterTiles(word) && word.card.stage >= minimumTypingStage
            case .koToEn:
                !word.meaningKo.isEmpty && word.card.stage >= minimumTypingStage
            case .dictation:
                canUseLetterTiles(word) && word.card.stage >= 3
            default:
                false
            }
        }
    }

    static func pickMode(for word: QuizWord, index: WordIndex, seed: String, config: SessionPlannerConfig) -> ExamItemKind {
        let available = availableModes(for: word, index: index, config: config)
        guard !available.isEmpty else { return word.hasCloze ? .clozeTyping : .koToEn }
        let weights = modeWeights(stage: word.card.stage)
        // 가중치 0(예: 새 단어의 빈칸 쓰기)은 다른 유형이 없을 때만 쓴다.
        let weighted = available.filter { (weights[$0] ?? 0) > 0 }
        guard !weighted.isEmpty else { return available[0] }
        let total = weighted.reduce(0) { $0 + (weights[$1] ?? 0) }
        var generator = SeededGenerator(word.id.uuidString, seed, "mode")
        var roll = Double.random(in: 0..<total, using: &generator)
        for mode in weighted {
            roll -= weights[mode] ?? 0
            if roll < 0 { return mode }
        }
        return weighted.last!
    }

    /// 배정한 유형을 못 쓰게 됐을 때 가능한 다른 유형 중 가장 가까운 것 (떠올리기 쪽을 우선).
    static func fallbackMode(for word: QuizWord, excluding mode: ExamItemKind, index: WordIndex, config: SessionPlannerConfig) -> ExamItemKind {
        let available = availableModes(for: word, index: index, config: config).filter { $0 != mode && $0 != .match }
        for preferred in [ExamItemKind.choice, .meaningChoice, .clozeChoiceWithoutTranslation, .clozeTyping] where available.contains(preferred) {
            return preferred
        }
        return word.hasCloze ? .clozeTyping : .koToEn
    }

    static func hint(forStage stage: Int) -> ClozeHint {
        switch stage {
        case ...4: .firstLetters
        case 5: .length
        default: ClozeHint.none
        }
    }

    /// 글자 조각·받아쓰기: 영문자(띄어쓰기 허용)로만 된 3~16글자 표제어.
    static func canUseLetterTiles(_ word: QuizWord) -> Bool {
        let letters = word.term.filter { $0 != " " }
        return !word.meaningKo.isEmpty
            && (3...16).contains(letters.count)
            && letters.allSatisfy { $0.isASCII && $0.isLetter }
    }

    /// 정답 글자(소문자) + 가짜 글자를 섞은 조각. 같은 단어·학습일이면 같은 배치.
    static func letterTiles(for word: QuizWord, seed: String) -> [String] {
        var generator = SeededGenerator(seed, word.id.uuidString, "tiles")
        let letters = word.term.lowercased().filter { $0 != " " }.map(String.init)
        // 가짜 글자는 자주 쓰는 글자 중 정답에 없는 것 (헷갈리되 억지스럽지 않게).
        let common = Array("eariotnslcudpmhgbfywkvxzjq").map(String.init).filter { !letters.contains($0) }
        let decoys = Array(common.prefix(10).shuffled(using: &generator).prefix(letterTileDecoyCount))
        return (letters + decoys).shuffled(using: &generator)
    }

    private static func canUseChoice(_ word: QuizWord) -> Bool {
        guard word.hasCloze else { return false }
        return !(word.isEnriched && choiceExcludedPOS.contains(word.pos))
    }

    // MARK: 단어 색인 (보기 후보를 여러 번 훑을 때 정규화 결과를 재사용)

    struct WordIndex {
        let words: [QuizWord]
        let byID: [UUID: QuizWord]
        private let terms: [UUID: String]
        private let meaningKeys: [UUID: Set<String>]
        private let nearMisses: [UUID: Set<String>]

        init(_ words: [QuizWord]) {
            self.words = words
            byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            terms = Dictionary(words.map { ($0.id, ExamText.normalize($0.term)) }, uniquingKeysWith: { first, _ in first })
            meaningKeys = Dictionary(words.map { ($0.id, $0.meaningKeys) }, uniquingKeysWith: { first, _ in first })
            nearMisses = Dictionary(words.map { ($0.id, Set($0.nearMiss.map(ExamText.normalize))) }, uniquingKeysWith: { first, _ in first })
        }

        func normalizedTerm(_ word: QuizWord) -> String {
            terms[word.id] ?? ExamText.normalize(word.term)
        }

        func keys(_ word: QuizWord) -> Set<String> {
            meaningKeys[word.id] ?? word.meaningKeys
        }

        /// 보기로 같이 두면 정답이 둘이 될 수 있는 사이인지 (같은 단어, 겹치는 뜻, near miss 관계).
        func conflicts(_ lhs: QuizWord, _ rhs: QuizWord) -> Bool {
            let lhsTerm = normalizedTerm(lhs)
            let rhsTerm = normalizedTerm(rhs)
            if lhs.id == rhs.id || lhsTerm == rhsTerm { return true }
            if !keys(lhs).isDisjoint(with: keys(rhs)) { return true }
            if nearMisses[lhs.id]?.contains(rhsTerm) == true || nearMisses[rhs.id]?.contains(lhsTerm) == true { return true }
            return false
        }
    }

    // MARK: M1 묶기

    struct MatchGroup: Equatable {
        var graded: [UUID]
        var fillers: [UUID]
    }

    static func buildMatchGroups(
        _ words: [QuizWord],
        allWords: [QuizWord],
        excludedFromFillers: Set<UUID>,
        seed: String,
        config: SessionPlannerConfig = .standard
    ) -> (groups: [MatchGroup], unplaceable: [QuizWord]) {
        guard !words.isEmpty else { return ([], []) }

        // 화면 수를 먼저 정하고 고르게 나눈다 (6개 → 5+1 대신 3+3).
        let screenCount = Int((Double(words.count) / Double(config.matchPairsPerScreen)).rounded(.up))
        let capacity = Int((Double(words.count) / Double(screenCount)).rounded(.up))
        var gradedGroups: [[QuizWord]] = []
        for word in words {
            if let index = gradedGroups.firstIndex(where: { group in
                group.count < capacity && !group.contains(where: { $0.meaningsOverlap(with: word) || sameTerm($0, word) })
            }) {
                gradedGroups[index].append(word)
            } else {
                gradedGroups.append([word])
            }
        }

        var groups: [MatchGroup] = []
        var unplaceable: [QuizWord] = []
        for (index, graded) in gradedGroups.enumerated() {
            var members = graded
            var fillers: [QuizWord] = []
            if graded.count < config.matchFillThreshold {
                let needed = config.matchPairsPerScreen - graded.count
                fillers = pickFillers(
                    count: needed,
                    for: members,
                    allWords: allWords,
                    excluded: excludedFromFillers,
                    seed: "\(seed)|filler|\(index)"
                )
                members += fillers
            }
            if members.count >= config.minimumMatchPairs {
                var generator = SeededGenerator(seed, "match", "\(index)")
                groups.append(MatchGroup(
                    graded: graded.map(\.id).shuffled(using: &generator),
                    fillers: fillers.map(\.id)
                ))
            } else {
                unplaceable += graded
            }
        }
        return (groups, unplaceable)
    }

    /// 채움 단어: 오늘 대상이 아닌 단어 중 stage ≥ 3 우선, 무작위. 모자라면 다른 대상 단어도 쓴다.
    static func pickFillers(
        count: Int,
        for members: [QuizWord],
        allWords: [QuizWord],
        excluded: Set<UUID>,
        seed: String
    ) -> [QuizWord] {
        guard count > 0 else { return [] }
        var generator = SeededGenerator(seed)
        let memberIDs = Set(members.map(\.id))
        let usable = allWords.filter { candidate in
            !memberIDs.contains(candidate.id)
                && !candidate.term.isEmpty
                && !candidate.meaningKeys.isEmpty
        }
        let nonTargets = usable.filter { !excluded.contains($0.id) }.shuffled(using: &generator)
        let targets = usable.filter { excluded.contains($0.id) }.shuffled(using: &generator)
        let ordered = nonTargets.filter { $0.card.stage >= 3 }
            + nonTargets.filter { $0.card.stage < 3 }
            + targets

        var chosen: [QuizWord] = []
        var screen = members
        for candidate in ordered where chosen.count < count {
            guard !screen.contains(where: { $0.meaningsOverlap(with: candidate) || sameTerm($0, candidate) }) else { continue }
            chosen.append(candidate)
            screen.append(candidate)
        }
        return chosen
    }

    private static func sameTerm(_ lhs: QuizWord, _ rhs: QuizWord) -> Bool {
        ExamText.normalize(lhs.term) == ExamText.normalize(rhs.term)
    }

    // MARK: 빈칸 고르기 보기 (5지선다)

    struct Distractor: Equatable {
        var word: QuizWord
        var rendered: String
    }

    /// 빈칸에 넣어 볼 오답 후보. 정답과 같은 활용형으로 보여 준다 (gave up ↔ turned down).
    /// 1) 둘 다 보강됐고 품사가 같으면 후보의 같은 활용형, 2) 아니면 후보 예문의 빈칸 표기 중 활용 분류·품사가 맞는 것.
    static func clozeDistractorPool(for target: QuizWord, index: WordIndex, limit: Int? = nil) -> [Distractor] {
        guard canUseChoice(target) else { return [] }
        let answer = target.clozeAnswer.lowercased()
        let targetIsPhrase = target.clozeAnswer.contains(" ")
        var seen: Set<String> = [answer]
        var pool: [Distractor] = []

        for candidate in index.words where !index.conflicts(target, candidate) {
            guard let rendered = renderedDistractor(candidate, for: target, targetIsPhrase: targetIsPhrase),
                  seen.insert(rendered.lowercased()).inserted else { continue }
            pool.append(Distractor(word: candidate, rendered: rendered))
            if let limit, pool.count >= limit { break }
        }
        return pool
    }

    private static func renderedDistractor(_ candidate: QuizWord, for target: QuizWord, targetIsPhrase: Bool) -> String? {
        if target.isEnriched, candidate.isEnriched, candidate.pos == target.pos,
           WordEntry.formKeys.contains(target.clozeForm) {
            let form = candidate.form(target.clozeForm)
            if !form.isEmpty { return form }
        }
        guard candidate.hasCloze,
              target.clozeFormClass != .other,
              candidate.clozeFormClass == target.clozeFormClass,
              candidate.clozeAnswer.contains(" ") == targetIsPhrase,
              partOfSpeechCompatible(target, candidate) else {
            return nil
        }
        var answer = candidate.clozeAnswer
        // 후보 예문의 문장 첫 단어였다면 대문자를 되돌린다 (정답 위치에 맞춘 대문자는 choiceOptions가 처리).
        if candidate.clozeSentence.trimmingCharacters(in: .whitespaces).hasPrefix("<>"), let first = answer.first {
            answer = first.lowercased() + answer.dropFirst()
        }
        return answer
    }

    /// 품사를 둘 다 알면 겹쳐야 하고, 모르면 활용 어미(-ed/-ing)가 문법 자리를 보장할 때만 허용한다.
    static func partOfSpeechCompatible(_ lhs: QuizWord, _ rhs: QuizWord) -> Bool {
        if !lhs.posHints.isEmpty, !rhs.posHints.isEmpty {
            return !lhs.posHints.isDisjoint(with: rhs.posHints)
        }
        return [.ed, .ing].contains(lhs.clozeFormClass)
    }

    /// CEFR 차이가 작을수록 +, 글자 수 차이 ≤ 3 이면 +, 최근 5문제에서 보기로 쓰였으면 −. 상위 8개 중 무작위 4개.
    static func clozeDistractors(
        for target: QuizWord,
        index: WordIndex,
        recentlyUsed: Set<String>,
        seed: String,
        config: SessionPlannerConfig = .standard
    ) -> [Distractor] {
        let pool = clozeDistractorPool(for: target, index: index)
        guard pool.count >= config.choiceDistractorCount else { return [] }

        let targetLevel = cefrOrder.firstIndex(of: target.cefr)
        return pickTop(pool, count: config.choiceDistractorCount, poolSize: config.choiceCandidatePoolSize, seed: seed, target: target) { candidate in
            var score = 0
            if let targetLevel, let level = cefrOrder.firstIndex(of: candidate.word.cefr) {
                score += 5 - min(abs(targetLevel - level), 5)
            }
            if abs(candidate.rendered.count - target.clozeAnswer.count) <= 3 { score += 3 }
            if recentlyUsed.contains(index.normalizedTerm(candidate.word)) { score -= 6 }
            return score
        }
    }

    static func clozeDistractors(
        for target: QuizWord,
        allWords: [QuizWord],
        recentlyUsed: Set<String> = [],
        seed: String,
        config: SessionPlannerConfig = .standard
    ) -> [Distractor] {
        clozeDistractors(for: target, index: WordIndex(allWords), recentlyUsed: recentlyUsed, seed: seed, config: config)
    }

    // MARK: 뜻 고르기 보기 (5지선다)

    /// 다른 단어의 한국어 뜻. 뜻이 겹치거나 표기가 같은 보기는 빼서 정답이 하나만 되게 한다.
    static func meaningDistractorPool(for target: QuizWord, index: WordIndex, limit: Int? = nil) -> [QuizWord] {
        guard !target.meaningKo.isEmpty else { return [] }
        var seen: Set<String> = [ExamText.normalizeMeaning(target.meaningKo)]
        var pool: [QuizWord] = []
        for candidate in index.words where !candidate.meaningKo.isEmpty && !index.conflicts(target, candidate) {
            guard seen.insert(ExamText.normalizeMeaning(candidate.meaningKo)).inserted else { continue }
            pool.append(candidate)
            if let limit, pool.count >= limit { break }
        }
        return pool
    }

    /// 같은 품사 +3, 뜻 길이가 비슷하면 +2, 최근 보기로 쓰였으면 −6. 상위 8개 중 무작위 4개.
    static func meaningDistractors(
        for target: QuizWord,
        index: WordIndex,
        recentlyUsed: Set<String>,
        seed: String,
        config: SessionPlannerConfig = .standard
    ) -> [QuizWord] {
        let pool = meaningDistractorPool(for: target, index: index)
        guard pool.count >= config.choiceDistractorCount else { return [] }
        return pickTop(pool, count: config.choiceDistractorCount, poolSize: config.choiceCandidatePoolSize, seed: seed, target: target) { candidate in
            var score = 0
            if !target.posHints.isDisjoint(with: candidate.posHints) { score += 3 }
            if abs(candidate.meaningKo.count - target.meaningKo.count) <= 4 { score += 2 }
            if recentlyUsed.contains(index.normalizedTerm(candidate)) { score -= 6 }
            return score
        }
    }

    /// 섞은 뒤 점수순 안정 정렬 → 상위 poolSize 개 중 무작위 count 개.
    private static func pickTop<T>(
        _ pool: [T],
        count: Int,
        poolSize: Int,
        seed: String,
        target: QuizWord,
        score: (T) -> Int
    ) -> [T] {
        var generator = SeededGenerator(seed, target.id.uuidString, "distractor")
        let top = pool.shuffled(using: &generator)
            .map { ($0, score($0)) }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 != rhs.element.1 ? lhs.element.1 > rhs.element.1 : lhs.offset < rhs.offset
            }
            .prefix(poolSize)
            .map(\.element.0)
        return Array(top.shuffled(using: &generator).prefix(count))
    }

    static func choiceOptions(answer: String, distractors: [String], word: QuizWord, seed: String) -> [String] {
        // 정답이 문장 첫 단어라면 보기도 첫 글자 대문자 (방어 코드).
        let capitalize = word.clozeSentence.trimmingCharacters(in: .whitespaces).hasPrefix("<>")
            || answer.first.map(\.isUppercase) == true
        let adjusted = distractors.map { capitalize ? capitalizedFirst($0) : $0 }
        var generator = SeededGenerator(seed, word.id.uuidString, "options")
        return ([answer] + adjusted).shuffled(using: &generator)
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: 순서·레슨

    /// 같은 유형이 3번 연속 나오지 않도록 재배치한다. 섞인 순서를 최대한 따르되,
    /// 한 유형이 너무 많이 남아 뒤에서 3연속이 불가피해지면 그 유형을 먼저 꺼낸다. 불가능하면 가능한 만큼만.
    static func arrangeAvoidingTriples<T>(_ items: [T], kindOf: (T) -> ExamItemKind) -> [T] {
        var remaining = items
        var result: [T] = []
        while !remaining.isEmpty {
            let lastTwo = result.suffix(2).map(kindOf)
            let blocked: ExamItemKind? = lastTwo.count == 2 && lastTwo[0] == lastTwo[1] ? lastTwo[0] : nil

            var counts: [ExamItemKind: Int] = [:]
            remaining.forEach { counts[kindOf($0), default: 0] += 1 }
            let dominant = counts.max { $0.value < $1.value }
            let others = remaining.count - (dominant?.value ?? 0)
            let mustTakeDominant = dominant.map { $0.key != blocked && $0.value >= 2 * others + 1 } ?? false

            let index: Int
            if mustTakeDominant, let kind = dominant?.key, let first = remaining.firstIndex(where: { kindOf($0) == kind }) {
                index = first
            } else {
                index = remaining.firstIndex { kindOf($0) != blocked } ?? 0
            }
            result.append(remaining.remove(at: index))
        }
        return result
    }

    /// 채점 문제 15개 단위로 레슨을 끊는다. 새 단어 카드와 그 문제 사이는 끊지 않는다.
    static func lessonBreaks(for items: [ExamPlanItem], lessonSize: Int) -> [Int] {
        var breaks: [Int] = []
        var count = 0
        for (index, item) in items.enumerated() {
            count += item.gradedWordIDs.count
            if count >= lessonSize, index < items.count - 1, item.kind != .newWord {
                breaks.append(index)
                count = 0
            }
        }
        return breaks
    }

    // MARK: 오답 다시 풀기 (SPEC §3.1-3, 채점 X)

    /// 틀린 단어를 원래 유형으로 한 번 더 낸다. M1이었던 단어는 새 짝 맞추기 화면으로 묶는다.
    static func replayItems(
        wrongWordIDs: [UUID],
        originalPlan: ExamPlan,
        allWords: [QuizWord],
        round: Int,
        config: SessionPlannerConfig = .standard
    ) -> [ExamPlanItem] {
        let wordsByID = Dictionary(allWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wrong = Set(wrongWordIDs)
        var matchWords: [QuizWord] = []
        var items: [ExamPlanItem] = []

        var covered: Set<UUID> = []
        for item in originalPlan.items where item.kind != .newWord {
            for id in item.wordIDs where wrong.contains(id) {
                guard let word = wordsByID[id], covered.insert(id).inserted else { continue }
                if item.kind == .match {
                    matchWords.append(word)
                } else {
                    items.append(ExamPlanItem(kind: item.kind, wordIDs: [id], options: item.options, hint: item.hint))
                }
            }
        }

        // 복습 카드에서 틀린 단어처럼 시험 계획에 없던 단어는 짝 맞추기로 다시 본다.
        matchWords += wrongWordIDs.filter { !covered.contains($0) }.compactMap { wordsByID[$0] }

        let (groups, unplaceable) = buildMatchGroups(
            matchWords,
            allWords: allWords,
            excludedFromFillers: wrong,
            seed: "replay|\(round)",
            config: config
        )
        let matchItems = groups.map { ExamPlanItem(kind: .match, wordIDs: $0.graded, fillerWordIDs: $0.fillers) }
        let fallbackItems = unplaceable.map { word in
            word.hasCloze
                ? ExamPlanItem(kind: .clozeTyping, wordIDs: [word.id], hint: hint(forStage: word.card.stage))
                : ExamPlanItem(kind: .koToEn, wordIDs: [word.id])
        }
        return matchItems + items + fallbackItems
    }
}
