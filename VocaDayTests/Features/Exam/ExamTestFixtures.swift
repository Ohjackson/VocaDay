import Foundation
@testable import VocaDay

enum ExamFixtures {
    static func verb(
        _ term: String,
        past: String,
        pp: String? = nil,
        ing: String,
        third: String,
        meaning: String,
        pos: String = "verb",
        stage: Int = 1,
        clozeForm: String = "past",
        nearMiss: [String] = [],
        cefr: String = "B1"
    ) -> QuizWord {
        let forms = [
            "base": term, "past": past, "past_participle": pp ?? past,
            "present_participle": ing, "third_person": third,
            "plural": "", "comparative": "", "superlative": "",
        ]
        let answer = forms[clozeForm] ?? term
        return QuizWord(
            id: UUID(),
            term: term,
            meaningKo: meaning,
            pos: pos,
            cefr: cefr,
            forms: forms,
            example: "Yesterday she \(answer) it at the office.",
            exampleKo: "\(meaning) 예문",
            clozeSentence: "Yesterday she <> it at the office.",
            clozeAnswer: answer,
            clozeForm: clozeForm,
            nearMiss: nearMiss,
            isEnriched: true,
            card: SRSCardState(stage: stage, nextLearningDay: 0, idkCount: stage == 0 ? 0 : 1)
        )
    }

    static func plain(_ term: String, meaning: String, stage: Int = 0, idk: Int = 0, next: Int = 0, createdAt: Date = Date()) -> QuizWord {
        QuizWord(
            id: UUID(),
            term: term,
            meaningKo: meaning,
            card: SRSCardState(stage: stage, nextLearningDay: next, idkCount: idk),
            createdAt: createdAt
        )
    }

    /// 보강 없이 사용자 예문만 있는 단어 (앱의 `VocaWord.quizWord`와 같은 경로).
    static func local(_ term: String, meaning: String, example: String, exampleKo: String = "번역", stage: Int = 0) -> QuizWord {
        QuizWord.local(
            term: term,
            meaningKo: meaning,
            exampleEn: example,
            exampleKo: exampleKo,
            card: SRSCardState(stage: stage, nextLearningDay: 0, idkCount: stage == 0 ? 0 : 1)
        )
    }

    /// 과거형 예문이 있는 보강 전 동사 12개 (뜻이 모두 다름).
    static func localPastVerbs(stage: (Int) -> Int = { _ in 0 }) -> [QuizWord] {
        let rows: [(String, String, String)] = [
            ("postpone", "v. 연기하다", "They postponed the meeting until Friday."),
            ("approve", "v. 승인하다", "The manager approved the budget yesterday."),
            ("confirm", "v. 확인하다", "She confirmed the reservation by email."),
            ("cancel", "v. 취소하다", "We canceled the order last week."),
            ("submit", "v. 제출하다", "He submitted the report on time."),
            ("review", "v. 검토하다", "The team reviewed the contract carefully."),
            ("launch", "v. 출시하다", "The company launched a new product."),
            ("hire", "v. 고용하다", "The firm hired three new engineers."),
            ("reduce", "v. 줄이다", "The factory reduced its costs."),
            ("expand", "v. 확장하다", "They expanded the office last year."),
            ("negotiate", "v. 협상하다", "She negotiated a better price."),
            ("attend", "v. 참석하다", "Everyone attended the seminar."),
        ]
        return rows.enumerated().map { index, row in
            local(row.0, meaning: row.1, example: row.2, stage: stage(index))
        }
    }

    static let pastVerbs: [QuizWord] = [
        verb("give up", past: "gave up", pp: "given up", ing: "giving up", third: "gives up", meaning: "포기하다", pos: "phrasal_verb", nearMiss: ["quit"]),
        verb("turn down", past: "turned down", ing: "turning down", third: "turns down", meaning: "거절하다", pos: "phrasal_verb"),
        verb("look after", past: "looked after", ing: "looking after", third: "looks after", meaning: "돌보다", pos: "phrasal_verb"),
        verb("put off", past: "put off", ing: "putting off", third: "puts off", meaning: "미루다", pos: "phrasal_verb"),
        verb("run into", past: "ran into", pp: "run into", ing: "running into", third: "runs into", meaning: "우연히 만나다", pos: "phrasal_verb"),
        verb("abandon", past: "abandoned", ing: "abandoning", third: "abandons", meaning: "버리다"),
        verb("persuade", past: "persuaded", ing: "persuading", third: "persuades", meaning: "설득하다"),
    ]
}
