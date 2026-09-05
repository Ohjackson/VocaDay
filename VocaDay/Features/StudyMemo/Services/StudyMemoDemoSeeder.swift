import Foundation
import SwiftData

/// 학습 메모 기능의 예시 데이터 생성과 기존 데이터 정리를 담당합니다.
enum StudyMemoDemoSeeder {
    private static let seededDataKey = "hasSeededStudyMemoData_v4"

    static func seedIfNeeded(existingMemos: [StudyMemo], in context: ModelContext) {
        try? repair(existingMemos: existingMemos, in: context)
        guard !hasSeededData else { return }

        try? replaceDemos(existingMemos: existingMemos, in: context)
    }

    static func recreateDemos(in context: ModelContext) throws {
        var existingMemos = try context.fetch(FetchDescriptor<StudyMemo>())
        try repair(existingMemos: existingMemos, in: context)
        existingMemos = try context.fetch(FetchDescriptor<StudyMemo>())
        try replaceDemos(existingMemos: existingMemos, in: context)
    }

    static func repair(existingMemos: [StudyMemo], in context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<StudyPageCategory>())
            .sorted { $0.createdAt < $1.createdAt }
        var categoryByNormalizedName: [String: StudyPageCategory] = [:]
        var replacementCategoryByID: [String: StudyPageCategory] = [:]
        var duplicateCategories: [StudyPageCategory] = []

        for category in categories {
            let key = normalizedCategoryName(category.name)
            guard !key.isEmpty else { continue }
            if let kept = categoryByNormalizedName[key] {
                replacementCategoryByID[category.id.uuidString] = kept
                duplicateCategories.append(category)
            } else {
                categoryByNormalizedName[key] = category
            }
        }

        for memo in existingMemos {
            if let replacement = replacementCategoryByID[memo.categoryID] {
                apply(replacement, to: memo)
            } else if !memo.categoryName.isEmpty,
                      let replacement = categoryByNormalizedName[normalizedCategoryName(memo.categoryName)],
                      memo.categoryID != replacement.id.uuidString {
                apply(replacement, to: memo)
            }
        }

        for category in duplicateCategories {
            context.delete(category)
        }

        let groupedDemos = Dictionary(grouping: existingMemos.filter {
            replaceableDemoTitles.contains($0.title)
        }, by: \StudyMemo.title)
        for duplicates in groupedDemos.values where duplicates.count > 1 {
            let kept = duplicates.max { $0.updatedAt < $1.updatedAt }
            for memo in duplicates where memo.id != kept?.id {
                context.delete(memo)
            }
        }

        try context.save()
    }

    private static func replaceDemos(
        existingMemos: [StudyMemo],
        in context: ModelContext
    ) throws {
        for memo in existingMemos where replaceableDemoTitles.contains(memo.title) {
            context.delete(memo)
        }

        let existingCategories = (try? context.fetch(FetchDescriptor<StudyPageCategory>())) ?? []
        var categoriesByName: [String: StudyPageCategory] = [:]
        for category in existingCategories where categoriesByName[category.name] == nil {
            categoriesByName[category.name] = category
        }

        for specification in demoCategorySpecifications where categoriesByName[specification.name] == nil {
            let category = StudyPageCategory(
                name: specification.name,
                colorRawValue: specification.color
            )
            context.insert(category)
            categoriesByName[specification.name] = category
        }

        for memo in makeDemos(categoriesByName: categoriesByName) {
            context.insert(memo)
        }
        try context.save()
        markSeeded()
    }

    private static func apply(_ category: StudyPageCategory, to memo: StudyMemo) {
        memo.categoryID = category.id.uuidString
        memo.categoryName = category.name
        memo.categoryColor = category.colorRawValue
    }

    private static func normalizedCategoryName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static var hasSeededData: Bool {
        UserDefaults.standard.bool(forKey: seededDataKey)
            || NSUbiquitousKeyValueStore.default.bool(forKey: seededDataKey)
    }

    private static func markSeeded() {
        UserDefaults.standard.set(true, forKey: seededDataKey)
        NSUbiquitousKeyValueStore.default.set(true, forKey: seededDataKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private static func makeDemos(
        categoriesByName: [String: StudyPageCategory]
    ) -> [StudyMemo] {
        let now = Date()
        let dictation = categoriesByName["받아쓰기"]
        let grammar = categoriesByName["문법"]
        let expression = categoriesByName["표현"]

        return [
            StudyMemo(
                title: "예시 · 공항 안내 방송 받아쓰기",
                icon: "",
                plainTextContent: """
                > 문장을 먼저 듣고 받아쓴 뒤 정답과 비교해 보세요.

                ## 내가 들은 문장

                Attention passengers on flight four eighty-two to Busan. Boarding will begin at gate twelve in approximately ten minutes.

                ## 정답 예문

                Attention, passengers on Flight 482 to Busan. Boarding will begin at Gate 12 in approximately ten minutes.

                ## 자연스러운 해석

                부산행 482편 승객 여러분께 안내드립니다. 약 10분 후 12번 탑승구에서 탑승을 시작하겠습니다.

                ---

                - **approximately**: 대략, 약
                - **boarding will begin**: 탑승이 시작될 예정이다
                """,
                categoryID: dictation?.id.uuidString ?? "",
                categoryName: dictation?.name ?? "받아쓰기",
                categoryColor: dictation?.colorRawValue ?? "blue",
                needsReview: true,
                createdAt: now.addingTimeInterval(-180),
                updatedAt: now.addingTimeInterval(-180)
            ),
            StudyMemo(
                title: "예시 · 현재완료와 과거시제",
                icon: "",
                plainTextContent: """
                # 현재완료: have/has + 과거분사

                과거에 시작한 일이 지금도 이어지거나 현재 결과와 연결될 때 사용합니다.

                ## 핵심 예문

                > She has worked at the company since 2021.

                그녀는 2021년부터 그 회사에서 일해 왔습니다.

                ## 과거시제와 비교

                > She worked at the company in 2021.

                그녀는 2021년에 그 회사에서 일했습니다. 지금도 근무하는지는 알 수 없습니다.

                ---

                - **since + 시작 시점**: since 2021
                - **for + 기간**: for five years
                """,
                categoryID: grammar?.id.uuidString ?? "",
                categoryName: grammar?.name ?? "문법",
                categoryColor: grammar?.colorRawValue ?? "purple",
                createdAt: now.addingTimeInterval(-120),
                updatedAt: now.addingTimeInterval(-120)
            ),
            StudyMemo(
                title: "예시 · 정중하게 부탁하기",
                icon: "",
                plainTextContent: """
                # Would you mind ~?

                업무 요청을 부드럽고 정중하게 전달할 때 유용한 표현입니다.

                ## 실전 예문

                > Would you mind sending me the revised schedule by noon?

                정오까지 수정된 일정을 보내 주시겠어요?

                ## 자연스러운 답변

                > Not at all. I'll send it as soon as I finish the final review.

                물론이죠. 최종 검토를 마치는 대로 보내 드릴게요.

                ---

                - `Would you mind` 뒤에는 동사원형이 아니라 **-ing** 형태를 사용합니다.
                - `Not at all`은 부탁을 받아들인다는 긍정적인 답변입니다.
                """,
                categoryID: expression?.id.uuidString ?? "",
                categoryName: expression?.name ?? "표현",
                categoryColor: expression?.colorRawValue ?? "green",
                createdAt: now.addingTimeInterval(-60),
                updatedAt: now.addingTimeInterval(-60)
            )
        ]
    }

    private static let replaceableDemoTitles: Set<String> = [
        "LC 파트 2 받아쓰기 루틴",
        "현재완료 vs 과거시제",
        "회의에서 의견 말하기",
        "예시 · 회의 일정 변경",
        "예시 · 공항 탑승 안내",
        "예시 · 현재완료 핵심",
        "예시 · 시간 전치사",
        "예시 · 이번 주 학습 계획",
        "예시 · 오늘의 오답 회고",
        "예시 · 공항 안내 방송 받아쓰기",
        "예시 · 현재완료와 과거시제",
        "예시 · 정중하게 부탁하기"
    ]

    private static let demoCategorySpecifications = [
        (name: "받아쓰기", color: "blue"),
        (name: "문법", color: "purple"),
        (name: "표현", color: "green")
    ]
}
