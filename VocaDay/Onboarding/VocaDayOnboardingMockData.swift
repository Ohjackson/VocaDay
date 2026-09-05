import Foundation

enum VocaDayOnboardingMockData {
    static let dayCards = [
        DayCardPresentation(
            title: "Day 1 · 출퇴근 영어",
            createdAt: Date(timeIntervalSince1970: 1_787_856_000),
            lastReviewedAt: Date(timeIntervalSince1970: 1_788_028_800),
            wordCount: 24,
            reviewSessionCount: 2
        ),
        DayCardPresentation(
            title: "Day 2 · 회의 표현",
            createdAt: Date(timeIntervalSince1970: 1_787_942_400),
            lastReviewedAt: nil,
            wordCount: 18,
            reviewSessionCount: 0
        )
    ]

    static let temporaryWords = [
        VocaWordJSON(
            english: "confirm",
            meaningKo: "확인하다",
            exampleEn: "Please confirm the meeting time.",
            exampleKo: "회의 시간을 확인해 주세요.",
            note: "예약이나 일정을 확정할 때 자주 사용",
            toeicTag: "동사 · Part 3"
        ),
        VocaWordJSON(
            english: "available",
            meaningKo: "이용 가능한",
            exampleEn: "The room is available after three.",
            exampleKo: "그 방은 3시 이후에 이용 가능합니다.",
            note: "사람의 시간이 된다는 뜻으로도 사용",
            toeicTag: "형용사 · Part 5"
        )
    ]

    static let studyMemoRows = [
        StudyPageRowPresentation(
            title: "공항 안내 방송 받아쓰기",
            isPinned: true,
            categoryName: "받아쓰기",
            categoryColorRawValue: "blue",
            previewText: "Passengers for Flight 482 should proceed to Gate 12.",
            updatedAt: Date(timeIntervalSince1970: 1_788_115_200)
        ),
        StudyPageRowPresentation(
            title: "관계대명사 정리",
            isPinned: false,
            categoryName: "문법",
            categoryColorRawValue: "purple",
            previewText: "who는 사람, which는 사물, that은 둘 다 사용할 수 있다.",
            updatedAt: Date(timeIntervalSince1970: 1_788_028_800)
        )
    ]
}
