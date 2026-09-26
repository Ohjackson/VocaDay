import Foundation

/// 단어 한 개가 복습·시험의 모든 유형을 낼 수 있는 데이터인지 검사한다.
///
/// 필요 조건
/// 1. 한국어 뜻 — 짝 맞추기·뜻 고르기·복습 카드
/// 2. 표제어(또는 활용형)가 그대로 들어간 영어 예문 — 빈칸 고르기·빈칸 쓰기의 정답 자리
/// 3. 예문의 한국어 번역 — 빈칸 문제의 맥락 힌트 (권장)
nonisolated enum WordDataCheck {
    enum Issue: String, Equatable, Sendable, CaseIterable {
        case missingMeaning
        case missingExample
        case exampleMissingWord
        /// 예문이 여러 줄인데 일부 줄에만 단어가 없다. 그 줄은 빈칸 문제에 쓰지 않는다.
        case someExampleLinesMissingWord
        case missingExampleTranslation
        /// 예문과 번역의 줄 수가 달라 줄끼리 짝을 맞출 수 없다.
        case exampleTranslationLineMismatch

        /// 저장을 막는 문제인지. 뜻이 없으면 어떤 문제도 만들 수 없다.
        var isBlocking: Bool { self == .missingMeaning }

        var message: String {
            switch self {
            case .missingMeaning: "한국어 뜻이 없어요"
            case .missingExample: "영어 예문이 없어 빈칸 문제를 만들 수 없어요"
            case .exampleMissingWord: "예문에 이 단어가 없어 빈칸 문제를 만들 수 없어요"
            case .someExampleLinesMissingWord: "단어가 없는 예문 줄이 있어요. 그 줄은 빈칸 문제에 쓰지 않아요"
            case .missingExampleTranslation: "예문 번역이 있으면 빈칸 문제의 힌트로 보여 줘요"
            case .exampleTranslationLineMismatch: "예문과 번역의 줄 수가 달라요. 1. / 2. 번호를 맞춰 주세요"
            }
        }
    }

    static func issues(english: String, meaningKo: String, exampleEn: String, exampleKo: String) -> [Issue] {
        let term = english.trimmingCharacters(in: .whitespacesAndNewlines)
        var issues: [Issue] = []
        if ExamText.strippingPartOfSpeechMarkers(meaningKo).isEmpty {
            issues.append(.missingMeaning)
        }
        if exampleEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingExample)
        } else if !term.isEmpty {
            let clozeCount = clozes(term: term, meaningKo: meaningKo, exampleEn: exampleEn).count
            if clozeCount == 0 {
                issues.append(.exampleMissingWord)
            } else if clozeCount < LocalCloze.exampleLines(exampleEn).count {
                issues.append(.someExampleLinesMissingWord)
            }
        }
        if !exampleEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if exampleKo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.missingExampleTranslation)
            } else if LocalCloze.exampleLines(exampleEn).count != LocalCloze.exampleLines(exampleKo).count {
                issues.append(.exampleTranslationLineMismatch)
            }
        }
        return issues
    }

    static func issues(for word: VocaWordJSON) -> [Issue] {
        issues(english: word.english, meaningKo: word.meaningKo, exampleEn: word.exampleEn, exampleKo: word.exampleKo)
    }

    /// 빈칸 문제를 낼 수 있는지 (뜻 + 단어가 들어간 예문).
    static func isQuizReady(_ issues: [Issue]) -> Bool {
        !issues.contains(.missingMeaning) && !issues.contains(.missingExample) && !issues.contains(.exampleMissingWord)
    }

    /// 빈칸을 만들 수 있는 예문 줄 중 `lineSeed` 번째 (줄 수로 나눈 나머지). 학습일을 넘기면 날마다 번갈아 나온다.
    static func cloze(term: String, meaningKo: String, exampleEn: String, lineSeed: Int = 0) -> LocalCloze.Result? {
        let all = clozes(term: term, meaningKo: meaningKo, exampleEn: exampleEn)
        guard !all.isEmpty else { return nil }
        let index = ((lineSeed % all.count) + all.count) % all.count
        return all[index]
    }

    static func clozes(term: String, meaningKo: String, exampleEn: String) -> [LocalCloze.Result] {
        LocalCloze.buildAll(
            term: term,
            example: exampleEn,
            allowsComparative: ExamText.partOfSpeechHints(meaningKo).contains("adjective")
        )
    }
}
