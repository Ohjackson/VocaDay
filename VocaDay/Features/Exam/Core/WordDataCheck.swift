import Foundation

/// 단어 한 개가 복습·시험 네 가지 유형을 모두 낼 수 있는 데이터인지 검사한다.
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
        case missingExampleTranslation

        /// 저장을 막는 문제인지. 뜻이 없으면 어떤 문제도 만들 수 없다.
        var isBlocking: Bool { self == .missingMeaning }

        var message: String {
            switch self {
            case .missingMeaning: "한국어 뜻이 없어요"
            case .missingExample: "영어 예문이 없어 빈칸 문제를 만들 수 없어요"
            case .exampleMissingWord: "예문에 이 단어가 없어 빈칸 문제를 만들 수 없어요"
            case .missingExampleTranslation: "예문 번역이 있으면 빈칸 문제의 힌트로 보여 줘요"
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
        } else if !term.isEmpty, cloze(term: term, meaningKo: meaningKo, exampleEn: exampleEn) == nil {
            issues.append(.exampleMissingWord)
        }
        if !exampleEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           exampleKo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingExampleTranslation)
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

    static func cloze(term: String, meaningKo: String, exampleEn: String) -> LocalCloze.Result? {
        LocalCloze.build(
            term: term,
            example: exampleEn,
            allowsComparative: ExamText.partOfSpeechHints(meaningKo).contains("adjective")
        )
    }
}
