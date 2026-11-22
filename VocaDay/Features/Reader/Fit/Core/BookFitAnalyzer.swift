import Foundation

/// 책 + 프로필 → 보고서. 순수 계산이라 어느 스레드에서나 부를 수 있다.
nonisolated struct BookFitAnalyzer: Sendable {
    var lemmatizer: any Lemmatizer
    var rules: FitLanguageRules
    var references: FitReferenceLists
    var criteria: BookFitCriteria
    /// 보고서에 남길 모르는 단어 수.
    var unknownWordLimit = 40

    init(
        lemmatizer: any Lemmatizer = FitEnglishLemmatizer(),
        rules: FitLanguageRules = .english,
        references: FitReferenceLists,
        criteria: BookFitCriteria = .standard
    ) {
        self.lemmatizer = lemmatizer
        self.rules = rules
        self.references = references
        self.criteria = criteria
    }

    /// 책·프로필·분석 규칙이 같으면 같은 값. 책 ID 가 같아도 내용이 바뀌면(다시 가져오기) 달라진다.
    func cacheKey(book: BookDocument, profile: VocabularyProfile) -> String {
        [
            book.id,
            "p" + profile.version,
            "a\(BookFitReport.analyzerVersion)",
            lemmatizer.identifier,
            "c\(criteria.extensiveCoverage)-\(criteria.intensiveCoverage)",
            "b" + Self.fingerprint(of: book),
        ].joined(separator: "|")
    }

    static func fingerprint(of book: BookDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return StableHash.of((try? encoder.encode(book)) ?? Data(book.id.utf8))
    }

    // MARK: 분석

    func analyze(_ book: BookDocument, profile: VocabularyProfile, now: Date = Date()) -> BookFitReport {
        let sentences = book.fitSentences
        let positions = sentences.map(\.position)
        var tokensByPosition: [ReadingPosition: [FitToken]] = [:]
        for (position, sentence) in sentences {
            tokensByPosition[position] = lemmatizer.tokens(in: sentence.text)
        }

        let glossaryForms = Set(book.glossary.flatMap { [$0.lemma] + $0.forms }.map(lemmatizer.normalize))
        let properSurfaces = properNounSurfaces(in: positions.compactMap { tokensByPosition[$0] }, profile: profile, glossaryForms: glossaryForms)

        var overall = Accumulator()
        var chapterAccumulators = book.chapters.map { _ in Accumulator() }
        var examCounts = WordCounter()
        var reviewCounts = WordCounter()
        var unknownCounts = WordCounter()

        for position in positions {
            let tokens = tokensByPosition[position] ?? []
            var sentence = SentenceTally(allTokenCount: tokens.count)
            for token in tokens {
                switch classify(token, properSurfaces: properSurfaces, profile: profile) {
                case .proper: sentence.proper += 1
                case .number: sentence.number += 1
                case .word(let headword, let known, let learning, let exam):
                    sentence.counted += 1
                    if known { sentence.known += 1 }
                    if let exam {
                        sentence.exam += 1
                        examCounts.add(exam, at: position)
                        if chapterAccumulators.indices.contains(position.chapter) {
                            chapterAccumulators[position.chapter].examTypes.insert(exam)
                        }
                    }
                    if learning {
                        sentence.review += 1
                        reviewCounts.add(headword, at: position)
                    } else if !known {
                        unknownCounts.add(headword, at: position)
                    }
                }
            }
            overall.add(sentence)
            if chapterAccumulators.indices.contains(position.chapter) {
                chapterAccumulators[position.chapter].add(sentence)
            }
        }

        var overallStats = overall.stats(criteria: criteria)
        overallStats.examTypeCount = examCounts.counts.count

        let chapters = book.chapters.indices.map { index in
            ChapterFit(index: index, title: book.chapters[index].title, stats: chapterAccumulators[index].stats(criteria: criteria))
        }

        let quality = BookQualityChecker(rules: rules, lemmatizer: lemmatizer).warnings(for: book, tokensByPosition: tokensByPosition)

        return BookFitReport(
            bookID: book.id,
            bookTitle: book.title,
            language: book.language,
            generatedAt: now,
            cacheKey: cacheKey(book: book, profile: profile),
            criteria: criteria,
            referenceSources: references.sources,
            profileWordbookCount: profile.wordbookCount,
            generalKnownCount: profile.settings.generalKnownCount,
            overall: overallStats,
            chapters: chapters,
            examWords: examCounts.sorted(),
            reviewWords: reviewCounts.sorted(),
            unknownWords: Array(unknownCounts.sorted().prefix(unknownWordLimit)),
            quality: quality.warnings,
            garbledRatio: quality.garbledRatio,
            topics: nil
        )
    }

    // MARK: 토큰 판정

    enum TokenClass: Equatable {
        case proper
        case number
        /// headword: 대표 원형, exam: 토익 목록 표제어.
        case word(headword: String, known: Bool, learning: Bool, exam: String?)
    }

    func classify(_ token: FitToken, properSurfaces: Set<String>, profile: VocabularyProfile) -> TokenClass {
        switch token.kind {
        case .number: return .number
        case .properNoun: return .proper
        case .word: break
        }
        if properSurfaces.contains(token.surface) { return .proper }

        let candidates = candidateHeadwords(token.keys)
        let learningHit = candidates.first(where: profile.isLearning)
        var knownHit = learningHit == nil ? candidates.first(where: profile.isKnown) : nil
        if learningHit == nil, knownHit == nil, !token.compoundParts.isEmpty,
           token.compoundParts.allSatisfy({ candidateHeadwords([$0]).contains(where: profile.isKnown) }) {
            knownHit = token.lemma
        }
        let exam = references.exam.headword(for: token.keys)
        let headword = learningHit ?? knownHit ?? references.general.headword(for: token.keys) ?? exam
            ?? token.keys.lazy.compactMap({ references.listedHeadwords(for: $0).first }).first ?? token.lemma
        return .word(headword: headword, known: knownHit != nil, learning: learningHit != nil, exam: exam)
    }

    /// 토큰 열쇠 + 그 열쇠가 가리키는 목록 표제어.
    private func candidateHeadwords(_ keys: [String]) -> [String] {
        var result: [String] = []
        func add(_ value: String?) {
            guard let value, !result.contains(value) else { return }
            result.append(value)
        }
        for key in keys {
            add(key)
            for headword in references.listedHeadwords(for: key) { add(headword) }
        }
        return result
    }

    /// 책 전체에서 고유명사로 볼 모양 (대소문자 그대로).
    /// NLTagger 가 이름으로 본 모양 + 책 어디에도 소문자로 나오지 않고 어느 목록·단어장·책 사전에도 없는 대문자 모양.
    /// 태거가 이름을 못 잡는 환경(iOS 시뮬레이터)과 문장 첫머리 이름("Elena, ...")을 함께 처리한다.
    func properNounSurfaces(in sentences: [[FitToken]], profile: VocabularyProfile, glossaryForms: Set<String> = []) -> Set<String> {
        var lowercaseSeen = Set<String>()
        for tokens in sentences {
            for token in tokens where token.surface.first?.isLowercase == true {
                lowercaseSeen.insert(lemmatizer.normalize(token.surface))
            }
        }

        var surfaces = Set<String>()
        for tokens in sentences {
            for token in tokens {
                guard token.surface.first?.isUppercase == true else { continue }
                if token.kind == .properNoun {
                    surfaces.insert(token.surface)
                    continue
                }
                let normalized = lemmatizer.normalize(token.surface)
                guard token.kind == .word, !lowercaseSeen.contains(normalized),
                      !glossaryForms.contains(normalized), !glossaryForms.contains(token.lemma) else { continue }
                // "I", 약어(TOEIC, HR)는 목록에 없더라도 이름이 아니다.
                guard token.surface.count > 1, token.surface.dropFirst().contains(where: \.isLowercase) else { continue }
                let candidates = candidateHeadwords(token.keys)
                let listed = candidates.contains { profile.isKnown($0) || profile.isLearning($0) }
                    || token.keys.contains { !references.listedHeadwords(for: $0).isEmpty }
                if !listed { surfaces.insert(token.surface) }
            }
        }
        // 소유격 모양도 같은 이름이다 ("Mina's").
        for surface in surfaces where !surface.contains("'") { surfaces.insert(surface + "'s"); surfaces.insert(surface + "’s") }
        return surfaces
    }
}

// MARK: - 집계 도우미

nonisolated private struct SentenceTally {
    var allTokenCount: Int
    var counted = 0
    var known = 0
    var proper = 0
    var number = 0
    var exam = 0
    var review = 0
}

nonisolated private struct Accumulator {
    var counted = 0
    var known = 0
    var proper = 0
    var number = 0
    var exam = 0
    var review = 0
    var sentences = 0
    var allTokens = 0
    var examTypes = Set<String>()

    mutating func add(_ sentence: SentenceTally) {
        counted += sentence.counted
        known += sentence.known
        proper += sentence.proper
        number += sentence.number
        exam += sentence.exam
        review += sentence.review
        sentences += 1
        allTokens += sentence.allTokenCount
    }

    func stats(criteria: BookFitCriteria) -> BookFitStats {
        var stats = BookFitStats()
        stats.tokenCount = counted
        stats.knownCount = known
        stats.properNounCount = proper
        stats.numberCount = number
        stats.sentenceCount = sentences
        stats.averageSentenceLength = sentences == 0 ? 0 : Double(allTokens) / Double(sentences)
        stats.examTokenCount = exam
        stats.examTypeCount = examTypes.count
        stats.reviewTokenCount = review
        stats.verdict = criteria.verdict(coverage: stats.coverage)
        return stats
    }
}

nonisolated private struct WordCounter {
    var counts: [String: (count: Int, first: ReadingPosition)] = [:]

    mutating func add(_ word: String, at position: ReadingPosition) {
        if let existing = counts[word] {
            counts[word] = (existing.count + 1, existing.first)
        } else {
            counts[word] = (1, position)
        }
    }

    func sorted() -> [FitWordCount] {
        counts.map { FitWordCount(word: $0.key, count: $0.value.count, firstPosition: $0.value.first) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                if lhs.firstPosition != rhs.firstPosition { return lhs.firstPosition < rhs.firstPosition }
                return lhs.word < rhs.word
            }
    }
}
