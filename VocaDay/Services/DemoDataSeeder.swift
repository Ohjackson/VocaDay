import Foundation
import SwiftData

enum DemoDataSeeder {
    private static let seededDemoDataKey = "hasSeededDemoData_v1"
    private static let seededStudyMemoDataKey = "hasSeededStudyMemoData_v1"

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

    static func seedStudyMemosIfNeeded(existingMemos: [StudyMemo], in context: ModelContext) {
        guard !hasSeededStudyMemoData else { return }

        guard existingMemos.isEmpty else {
            markStudyMemoDataSeeded()
            return
        }

        for memo in studyMemoDemos {
            context.insert(memo)
        }
        markStudyMemoDataSeeded()
        try? context.save()
    }

    private static var hasSeededDemoData: Bool {
        UserDefaults.standard.bool(forKey: seededDemoDataKey)
            || NSUbiquitousKeyValueStore.default.bool(forKey: seededDemoDataKey)
    }

    private static var hasSeededStudyMemoData: Bool {
        UserDefaults.standard.bool(forKey: seededStudyMemoDataKey)
            || NSUbiquitousKeyValueStore.default.bool(forKey: seededStudyMemoDataKey)
    }

    private static func markSeeded() {
        UserDefaults.standard.set(true, forKey: seededDemoDataKey)
        NSUbiquitousKeyValueStore.default.set(true, forKey: seededDemoDataKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private static func markStudyMemoDataSeeded() {
        UserDefaults.standard.set(true, forKey: seededStudyMemoDataKey)
        NSUbiquitousKeyValueStore.default.set(true, forKey: seededStudyMemoDataKey)
        NSUbiquitousKeyValueStore.default.synchronize()
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

private var studyMemoDemos: [StudyMemo] {
    let now = Date()
    return [
        StudyMemo(
            title: "예시 · 회의 일정 변경",
            icon: "🎧",
            coverStyle: "blue",
            blocks: [
                StudyPageBlock(kind: .callout, text: "외부 음원을 들은 뒤 정답을 펼쳐 비교하는 받아쓰기 페이지입니다."),
                StudyPageBlock(kind: .heading2, text: "내가 받아쓴 문장"),
                StudyPageBlock(kind: .quote, text: "The meeting has been postponed to Friday."),
                StudyPageBlock(kind: .toggle, text: "정답 보기", detail: "The meeting has been postponed until Friday."),
                StudyPageBlock(kind: .heading2, text: "해석"),
                StudyPageBlock(text: "회의가 금요일로 연기되었습니다."),
                StudyPageBlock(kind: .toDo, text: "to와 until의 차이를 다시 듣기"),
                StudyPageBlock(kind: .toDo, text: "postponed의 끝소리 확인하기")
            ],
            needsReview: true,
            createdAt: now.addingTimeInterval(-360),
            updatedAt: now.addingTimeInterval(-360)
        ),
        StudyMemo(
            title: "예시 · 공항 탑승 안내",
            icon: "🎧",
            blocks: [
                StudyPageBlock(kind: .heading1, text: "Airport announcement"),
                StudyPageBlock(kind: .quote, text: "Passengers should proceed to gate twelve."),
                StudyPageBlock(kind: .heading2, text: "자연스러운 해석"),
                StudyPageBlock(text: "승객들은 12번 탑승구로 이동해야 합니다."),
                StudyPageBlock(kind: .callout, text: "proceed to는 ‘~로 이동하다’라는 안내 방송의 빈출 표현입니다."),
                StudyPageBlock(kind: .divider),
                StudyPageBlock(kind: .bulletedList, text: "passenger: 승객"),
                StudyPageBlock(kind: .bulletedList, text: "gate: 탑승구")
            ],
            createdAt: now.addingTimeInterval(-300),
            updatedAt: now.addingTimeInterval(-300)
        ),
        StudyMemo(
            title: "예시 · 현재완료 핵심",
            icon: "📚",
            coverStyle: "sand",
            blocks: [
                StudyPageBlock(kind: .callout, text: "have/has + 과거분사"),
                StudyPageBlock(kind: .heading2, text: "언제 사용할까?"),
                StudyPageBlock(text: "과거에 시작된 일이나 경험이 현재와 연결될 때 사용합니다."),
                StudyPageBlock(kind: .heading2, text: "예문"),
                StudyPageBlock(kind: .quote, text: "I have finished the report."),
                StudyPageBlock(text: "나는 보고서를 끝냈습니다."),
                StudyPageBlock(kind: .heading2, text: "주의점"),
                StudyPageBlock(kind: .toDo, text: "yesterday처럼 명확하게 끝난 과거 시점과 함께 쓰지 않기")
            ],
            isPinned: true,
            createdAt: now.addingTimeInterval(-240),
            updatedAt: now.addingTimeInterval(-240)
        ),
        StudyMemo(
            title: "예시 · 시간 전치사",
            icon: "🧠",
            blocks: [
                StudyPageBlock(kind: .heading1, text: "at · on · in"),
                StudyPageBlock(kind: .table, tableColumns: ["전치사", "사용", "예시"], tableRows: [
                    ["at", "정확한 시각", "at 9 a.m."],
                    ["on", "요일·날짜", "on Monday"],
                    ["in", "월·연도·기간", "in August"]
                ]),
                StudyPageBlock(kind: .heading2, text: "예문"),
                StudyPageBlock(kind: .quote, text: "The workshop starts at 9 a.m. on Monday."),
                StudyPageBlock(kind: .callout, text: "시간의 범위가 좁으면 at, 날짜는 on, 넓은 기간은 in")
            ],
            createdAt: now.addingTimeInterval(-180),
            updatedAt: now.addingTimeInterval(-180)
        ),
        StudyMemo(
            title: "예시 · 이번 주 학습 계획",
            icon: "🎯",
            coverStyle: "green",
            blocks: [
                StudyPageBlock(kind: .heading1, text: "이번 주 목표"),
                StudyPageBlock(kind: .toDo, text: "데이 0 단어를 매일 한 번 복습하기"),
                StudyPageBlock(kind: .toDo, text: "LC 문장을 하루 2개씩 받아쓰기"),
                StudyPageBlock(kind: .toDo, text: "헷갈린 문법을 예문과 함께 정리하기"),
                StudyPageBlock(kind: .divider),
                StudyPageBlock(kind: .heading2, text: "이번 주 회고"),
                StudyPageBlock(text: "잘한 점과 다음 주에 바꿀 점을 기록해 보세요.")
            ],
            isPinned: true,
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(-120)
        ),
        StudyMemo(
            title: "예시 · 오늘의 오답 회고",
            icon: "✅",
            blocks: [
                StudyPageBlock(kind: .heading2, text: "오늘 자주 틀린 표현"),
                StudyPageBlock(text: "여기에 틀린 표현을 기록하세요."),
                StudyPageBlock(kind: .heading2, text: "틀린 이유"),
                StudyPageBlock(kind: .bulletedList, text: "뜻을 정확히 구분하지 못함"),
                StudyPageBlock(kind: .bulletedList, text: "문장 속 발음을 놓침"),
                StudyPageBlock(kind: .heading2, text: "다음 복습"),
                StudyPageBlock(kind: .toDo, text: "예문을 소리 내어 세 번 읽기"),
                StudyPageBlock(kind: .toDo, text: "내일 다시 확인하기")
            ],
            needsReview: true,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now.addingTimeInterval(-60)
        )
    ]
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
