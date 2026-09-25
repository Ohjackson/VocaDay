import Foundation

nonisolated struct GradingOptions: Equatable, Sendable {
    /// 긴 단어일수록 오타를 더 봐준다 (5~8글자 1자, 9글자 이상 2자).
    var allowsTypo = true
    /// near miss(다른 활용형·유의어)면 벌점 없이 한 번 더 입력.
    var allowsNearMissRetry = true

    static let standard = GradingOptions()
}

nonisolated enum GradeOutcome: Equatable, Sendable {
    case correct
    /// 정답 처리 + "오타 주의" 표시.
    case typo(expected: String)
    /// 다시 입력할 기회를 준다 (채점 보류).
    case nearMiss(message: String)
    case wrong(expected: String)

    var isCorrect: Bool {
        switch self {
        case .correct, .typo: true
        case .nearMiss, .wrong: false
        }
    }

    var isFinal: Bool {
        if case .nearMiss = self { return false }
        return true
    }
}

/// 입력형(M3·M4) 채점 (SPEC §4.6). UI와 분리된 순수 로직.
nonisolated enum AnswerGrader {
    static let typoMinimumLength = 5

    /// 정답으로 인정하는 오타 거리. 철자 시험이 아니라 단어를 떠올렸는지를 보려는 것이므로 길이에 비례해 봐준다.
    static func allowedTypoDistance(forLength length: Int) -> Int {
        switch length {
        case ..<typoMinimumLength: 0
        case typoMinimumLength...8: 1
        default: 2
        }
    }

    static let formLabels: [String: String] = [
        "base": "기본형",
        "past": "과거형",
        "past_participle": "과거분사",
        "present_participle": "-ing형",
        "third_person": "3인칭 단수형",
        "plural": "복수형",
        "comparative": "비교급",
        "superlative": "최상급",
    ]

    /// M3 예문 빈칸 쓰기. 정답: clozeAnswer + clozeAccepted. near miss: 같은 단어의 다른 활용형.
    static func gradeCloze(
        _ input: String,
        word: QuizWord,
        isRetry: Bool = false,
        options: GradingOptions = .standard
    ) -> GradeOutcome {
        let accepted = [word.clozeAnswer] + word.clozeAccepted
        let requiredLabel = formLabels[word.clozeForm].map { " (\($0)\(josaEuro($0)) 써 보세요)" } ?? ""
        var formValues = WordEntry.formKeys.map(word.form).filter { !$0.isEmpty }
        if formValues.isEmpty, !word.term.contains(" ") {
            // 보강 전 단어: 규칙 활용형을 쓴 경우도 "형태가 달라요"로 한 번 더 기회를 준다.
            formValues = LocalCloze.inflections(of: word.term).map(\.form)
        }
        let otherForms = formValues
            .map { (value: $0, message: "형태가 달라요\(requiredLabel)") }
        return grade(input, accepted: accepted, nearMisses: otherForms, isRetry: isRetry, options: options)
    }

    /// M4 한국어 → 영어 쓰기. 정답: term, forms.base, termVariants.
    /// near miss: nearMiss 목록의 다른 단어, 또는 target의 다른 활용형.
    static func gradeKoToEn(
        _ input: String,
        word: QuizWord,
        isRetry: Bool = false,
        options: GradingOptions = .standard
    ) -> GradeOutcome {
        let accepted = [word.term, word.form("base")] + word.termVariants
        let initial = word.term.first.map { String($0).lowercased() } ?? ""
        let synonyms = word.nearMiss.map {
            (value: $0, message: "뜻은 맞지만 연습 중인 단어가 아니에요 (\(initial)로 시작)")
        }
        let otherForms = WordEntry.formKeys
            .filter { $0 != "base" }
            .map(word.form)
            .filter { !$0.isEmpty }
            .map { (value: $0, message: "기본형으로 써 주세요") }
        return grade(input, accepted: accepted, nearMisses: synonyms + otherForms, isRetry: isRetry, options: options)
    }

    static func grade(
        _ input: String,
        accepted: [String],
        nearMisses: [(value: String, message: String)],
        isRetry: Bool,
        options: GradingOptions
    ) -> GradeOutcome {
        let acceptedDisplay = accepted.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let expected = acceptedDisplay.first ?? ""
        let normalizedInput = ExamText.normalize(input)
        guard !normalizedInput.isEmpty else { return .wrong(expected: expected) }

        let acceptedNormalized = acceptedDisplay.map(ExamText.normalize)
        if acceptedNormalized.contains(normalizedInput) {
            return .correct
        }

        // 다른 활용형·유의어를 정확히 쓴 경우는 오타로 봐주지 않는다 (abandons ≠ abandon 오타).
        if let nearMiss = nearMisses.first(where: {
            let value = ExamText.normalize($0.value)
            return value == normalizedInput && !acceptedNormalized.contains(value)
        }) {
            return options.allowsNearMissRetry && !isRetry
                ? .nearMiss(message: nearMiss.message)
                : .wrong(expected: expected)
        }

        if options.allowsTypo {
            for (index, answer) in acceptedNormalized.enumerated() {
                let distance = ExamText.levenshtein(normalizedInput, answer)
                if distance > 0, distance <= allowedTypoDistance(forLength: answer.count) {
                    return .typo(expected: acceptedDisplay[index])
                }
            }
        }

        // 떠올리긴 했지만 철자가 조금 더 틀린 경우: 벌점 없이 첫 글자·글자 수 힌트와 함께 한 번 더.
        if options.allowsNearMissRetry, !isRetry,
           let answer = acceptedNormalized.first, answer.count >= 4,
           ExamText.levenshtein(normalizedInput, answer) <= allowedTypoDistance(forLength: answer.count) + 1 {
            let first = acceptedDisplay.first?.first.map(String.init) ?? ""
            return .nearMiss(message: "철자가 조금 달라요. \(first)로 시작하는 \(answer.count)글자예요. 한 번 더 써 보세요")
        }
        return .wrong(expected: expected)
    }

    /// 받침 유무에 따른 "으로/로" (ㄹ 받침은 "로").
    static func josaEuro(_ word: String) -> String {
        guard let scalar = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return "으로" }
        let jong = (scalar.value - 0xAC00) % 28
        return jong == 0 || jong == 8 ? "로" : "으로"
    }

    // MARK: 힌트 (SPEC §4 M3)

    /// firstLetters: "g _ _ _  u _", length: "(4·2글자)" 또는 "(7글자)", none: "".
    static func hint(for answer: String, style: ClozeHint) -> String {
        let tokens = answer.split(separator: " ").map(String.init)
        switch style {
        case .firstLetters:
            return tokens.map { token in
                token.enumerated().map { index, character in
                    index == 0 || !character.isLetter ? String(character) : "_"
                }.joined(separator: " ")
            }.joined(separator: "   ")
        case .length:
            let counts = tokens.map { $0.filter(\.isLetter).count }
            return "(\(counts.map(String.init).joined(separator: "·"))글자)"
        case .none:
            return ""
        }
    }
}
