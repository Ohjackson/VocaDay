import Foundation
import SwiftData

enum DemoDataSeeder {
    private static let seededDemoDataKey = "hasSeededDemoData_v1"
    private static let seededStudyDemoDataKey = "hasSeededStudyDemoData_v1"

    static func seedIfNeeded(existingDays: [VocabularyDay], in context: ModelContext) {
        if let demoDay = existingDays.first(where: { $0.title == demoDayTitle || $0.title == legacyDemoDayTitle }) {
            seedMissingDemoWords(into: demoDay, in: context)
            markSeeded()
        } else if hasSeededDemoData {
            return
        } else {
            seedDemoDay(in: context)
            markSeeded()
        }

        try? context.save()
    }

    static func seedStudyDataIfNeeded(
        existingLCDays: [LCDictationDay],
        existingGrammarNotes: [GrammarNote],
        existingCustomPages: [CustomStudyPage],
        in context: ModelContext
    ) {
        guard !hasSeededStudyDemoData else { return }

        if existingLCDays.isEmpty {
            seedLCDemos(in: context)
        }
        if existingGrammarNotes.isEmpty {
            seedGrammarDemos(in: context)
        }
        if existingCustomPages.isEmpty {
            seedCustomPageDemos(in: context)
        }

        markStudyDemoDataSeeded()
        try? context.save()
    }

    private static var hasSeededDemoData: Bool {
        UserDefaults.standard.bool(forKey: seededDemoDataKey)
            || NSUbiquitousKeyValueStore.default.bool(forKey: seededDemoDataKey)
    }

    private static var hasSeededStudyDemoData: Bool {
        UserDefaults.standard.bool(forKey: seededStudyDemoDataKey)
            || NSUbiquitousKeyValueStore.default.bool(forKey: seededStudyDemoDataKey)
    }

    private static func markSeeded() {
        UserDefaults.standard.set(true, forKey: seededDemoDataKey)
        NSUbiquitousKeyValueStore.default.set(true, forKey: seededDemoDataKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private static func markStudyDemoDataSeeded() {
        UserDefaults.standard.set(true, forKey: seededStudyDemoDataKey)
        NSUbiquitousKeyValueStore.default.set(true, forKey: seededStudyDemoDataKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private static func seedLCDemos(in context: ModelContext) {
        let demos: [(title: String, lines: [String])] = [
            (
                "LC 예시 1 · 일정 변경",
                [
                    "The meeting has been postponed until Friday.",
                    "Please confirm your attendance by noon."
                ]
            ),
            (
                "LC 예시 2 · 공항 안내",
                [
                    "Passengers should proceed to gate twelve.",
                    "The flight is expected to depart on time."
                ]
            )
        ]

        for (index, demo) in demos.enumerated() {
            let day = LCDictationDay(
                title: demo.title,
                createdAt: Date().addingTimeInterval(TimeInterval(-120 + index))
            )
            context.insert(day)

            for (lineIndex, text) in demo.lines.enumerated() {
                let note = LCDictationNote(
                    text: text,
                    createdAt: day.createdAt.addingTimeInterval(TimeInterval(lineIndex)),
                    day: day
                )
                context.insert(note)
                if !day.noteList.contains(where: { $0.id == note.id }) {
                    day.appendNote(note)
                }
            }
        }
    }

    private static func seedGrammarDemos(in context: ModelContext) {
        let demos: [(title: String, markdown: String)] = [
            (
                "예시 · 현재완료 핵심",
                """
                # 현재완료

                ## 형태
                have/has + 과거분사

                - 경험: I have visited Busan.
                - 완료: She has finished the report.

                **핵심:** 과거의 일이 현재와 연결될 때 사용합니다.
                """
            ),
            (
                "예시 · 전치사 시간 표현",
                """
                # 시간 전치사

                | 전치사 | 사용 | 예시 |
                | --- | --- | --- |
                | at | 정확한 시각 | at 9 a.m. |
                | on | 요일·날짜 | on Monday |
                | in | 월·연도·기간 | in August |

                **핵심:** 좁은 시점은 at, 날짜는 on, 넓은 기간은 in을 사용합니다.
                """
            )
        ]

        for (index, demo) in demos.enumerated() {
            let date = Date().addingTimeInterval(TimeInterval(-100 + index))
            context.insert(
                GrammarNote(
                    title: demo.title,
                    markdown: demo.markdown,
                    createdAt: date,
                    updatedAt: date
                )
            )
        }
    }

    private static func seedCustomPageDemos(in context: ModelContext) {
        let markdownPage = CustomStudyPage(
            title: "예시 · 주간 학습 회고",
            iconName: "checklist",
            kind: .markdown,
            markdown: """
            # 이번 주 학습 회고

            ## 잘한 점
            - 매일 단어를 복습했습니다.

            ## 다음 목표
            - LC 문장을 하루 2개씩 받아씁니다.
            - 틀린 문법을 예문과 함께 정리합니다.
            """,
            createdAt: Date().addingTimeInterval(-80),
            updatedAt: Date().addingTimeInterval(-80)
        )
        context.insert(markdownPage)

        let topicColumn = StudyTableColumn(title: "학습 항목", kind: .text)
        let goalColumn = StudyTableColumn(title: "이번 주 목표", kind: .text)
        let completedColumn = StudyTableColumn(title: "완료", kind: .checkbox)
        let columns = [topicColumn, goalColumn, completedColumn]
        let rows = [
            StudyTableRow(values: [
                topicColumn.id.uuidString: "단어",
                goalColumn.id.uuidString: "Day 1~3 복습",
                completedColumn.id.uuidString: "false"
            ]),
            StudyTableRow(values: [
                topicColumn.id.uuidString: "LC",
                goalColumn.id.uuidString: "받아쓰기 4문장",
                completedColumn.id.uuidString: "false"
            ])
        ]
        let tablePage = CustomStudyPage(
            title: "예시 · 주간 학습 계획",
            iconName: "tablecells",
            kind: .table,
            columns: columns,
            rows: rows,
            createdAt: Date().addingTimeInterval(-70),
            updatedAt: Date().addingTimeInterval(-70)
        )
        context.insert(tablePage)
    }

    private static func seedDemoDay(in context: ModelContext) {
        let day = VocabularyDay(
            title: demoDayTitle,
            createdAt: Date().addingTimeInterval(-60)
        )
        context.insert(day)
        insert(words: demoWords, into: day, in: context)
    }

    private static func seedMissingDemoWords(into day: VocabularyDay, in context: ModelContext) {
        let existingEnglish = Set(day.wordList.map(\.english.normalizedEnglish))
        insert(
            words: demoWords.filter { !existingEnglish.contains($0.english.normalizedEnglish) },
            into: day,
            in: context
        )
    }

    private static func insert(words: [SeedWord], into day: VocabularyDay, in context: ModelContext) {
        for seed in words {
            let word = VocaWord(
                english: seed.english,
                meaningKo: seed.meaningKo,
                exampleEn: seed.exampleEn,
                exampleKo: seed.exampleKo,
                note: seed.note,
                toeicTag: seed.toeicTag,
                reviewCount: seed.reviewCount,
                correctCount: seed.correctCount,
                wrongCount: seed.wrongCount,
                masteryLevel: seed.masteryLevel,
                status: seed.status.rawValue,
                nextReviewAt: seed.nextReviewAt,
                lastReviewedAt: seed.lastReviewedAt,
                day: day
            )

            context.insert(word)
            day.appendWord(word)
        }
    }
}

private let demoDayTitle = "데이 0"
private let legacyDemoDayTitle = "Day 0"

private struct SeedWord {
    let english: String
    let meaningKo: String
    let exampleEn: String
    let exampleKo: String
    let note: String
    let toeicTag: String
    let reviewCount: Int
    let correctCount: Int
    let wrongCount: Int
    let masteryLevel: Int
    let status: WordStatus
    let nextReviewAt: Date
    let lastReviewedAt: Date?

    init(
        english: String,
        meaningKo: String,
        exampleEn: String,
        exampleKo: String,
        note: String,
        toeicTag: String,
        reviewCount: Int = 0,
        correctCount: Int = 0,
        wrongCount: Int = 0,
        masteryLevel: Int = 0,
        status: WordStatus = .new,
        nextReviewOffsetDays: Int = 0,
        lastReviewedOffsetDays: Int? = nil
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        self.english = english
        self.meaningKo = meaningKo
        self.exampleEn = exampleEn
        self.exampleKo = exampleKo
        self.note = note
        self.toeicTag = toeicTag
        self.reviewCount = reviewCount
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.masteryLevel = masteryLevel
        self.status = status
        self.nextReviewAt = calendar.date(byAdding: .day, value: nextReviewOffsetDays, to: today) ?? today

        if let lastReviewedOffsetDays {
            self.lastReviewedAt = calendar.date(byAdding: .day, value: lastReviewedOffsetDays, to: today)
        } else {
            self.lastReviewedAt = nil
        }
    }
}

private let demoWords: [SeedWord] = [
    SeedWord(
        english: "accommodation",
        meaningKo: "숙박 시설",
        exampleEn: "The conference fee includes accommodation for two nights.",
        exampleKo: "회의 참가비에는 2박 숙박이 포함됩니다.",
        note: "formal business noun",
        toeicTag: "Travel"
    ),
    SeedWord(
        english: "reimburse",
        meaningKo: "상환하다, 변제하다",
        exampleEn: "The company will reimburse employees for travel expenses.",
        exampleKo: "회사는 직원들의 출장비를 상환할 것입니다.",
        note: "expense reports",
        toeicTag: "Finance",
        reviewCount: 1,
        correctCount: 1,
        masteryLevel: 1,
        status: .learning,
        nextReviewOffsetDays: 0,
        lastReviewedOffsetDays: -1
    ),
    SeedWord(
        english: "itinerary",
        meaningKo: "여행 일정표",
        exampleEn: "Please check the itinerary before leaving for the airport.",
        exampleKo: "공항으로 출발하기 전에 일정표를 확인해 주세요.",
        note: "travel documents",
        toeicTag: "Travel"
    ),
    SeedWord(
        english: "mandatory",
        meaningKo: "의무적인, 필수의",
        exampleEn: "Attendance at the safety workshop is mandatory.",
        exampleKo: "안전 워크숍 참석은 필수입니다.",
        note: "policy wording",
        toeicTag: "Office"
    ),
    SeedWord(
        english: "inventory",
        meaningKo: "재고, 물품 목록",
        exampleEn: "The manager reviewed the inventory before placing an order.",
        exampleKo: "관리자는 주문하기 전에 재고를 검토했습니다.",
        note: "warehouse context",
        toeicTag: "Retail",
        reviewCount: 2,
        correctCount: 1,
        wrongCount: 1,
        masteryLevel: 1,
        status: .learning,
        nextReviewOffsetDays: 0,
        lastReviewedOffsetDays: -1
    ),
    SeedWord(
        english: "authorize",
        meaningKo: "승인하다, 권한을 부여하다",
        exampleEn: "Only the director can authorize this purchase.",
        exampleKo: "이 구매는 이사만 승인할 수 있습니다.",
        note: "approval flow",
        toeicTag: "Management"
    ),
    SeedWord(
        english: "renovation",
        meaningKo: "개조, 보수 공사",
        exampleEn: "The lobby will be closed during the renovation.",
        exampleKo: "로비는 보수 공사 동안 폐쇄됩니다.",
        note: "facilities",
        toeicTag: "Real Estate"
    ),
    SeedWord(
        english: "defective",
        meaningKo: "결함이 있는",
        exampleEn: "Customers may return defective products within thirty days.",
        exampleKo: "고객은 결함이 있는 제품을 30일 이내에 반품할 수 있습니다.",
        note: "returns policy",
        toeicTag: "Customer Service",
        reviewCount: 3,
        correctCount: 1,
        wrongCount: 2,
        masteryLevel: 0,
        status: .weak,
        nextReviewOffsetDays: 0,
        lastReviewedOffsetDays: -1
    ),
    SeedWord(
        english: "deadline",
        meaningKo: "마감일",
        exampleEn: "The deadline for submitting the report is Friday.",
        exampleKo: "보고서 제출 마감일은 금요일입니다.",
        note: "schedule",
        toeicTag: "Office"
    ),
    SeedWord(
        english: "adjacent",
        meaningKo: "인접한",
        exampleEn: "The meeting room is adjacent to the main office.",
        exampleKo: "회의실은 본사무실과 인접해 있습니다.",
        note: "location",
        toeicTag: "Facilities"
    )
]
