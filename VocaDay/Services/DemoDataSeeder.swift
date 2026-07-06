import Foundation
import SwiftData

enum DemoDataSeeder {
    static func seedIfNeeded(existingDays: [VocabularyDay], in context: ModelContext) {
        if let demoDay = existingDays.first(where: { $0.title == demoDayTitle }) {
            seedMissingDemoWords(into: demoDay, in: context)
        } else {
            seedDemoDay(in: context)
        }

        try? context.save()
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
        let existingEnglish = Set(day.words.map(\.english.normalizedEnglish))
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
            day.words.append(word)
        }
    }
}

private let demoDayTitle = "Day 0"

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
