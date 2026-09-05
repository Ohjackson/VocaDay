import XCTest
import SwiftUI
@testable import VocaDay

@MainActor
final class ComponentSpotlightOnboardingTests: XCTestCase {
    func testEveryStepMatchesApprovedSnapshot() {
        let snapshots = SpotlightStep.allCases.map { step in
            "\(step.rawValue + 1)|\(step.target.rawValue)|\(step.placement.rawValue)|\(step.section.title)|\(step.title)"
        }

        XCTAssertEqual(snapshots, [
            "1|dayCollection|bottom|데이|데이에서 학습 묶음을 확인하세요",
            "2|createDayButton|bottom|데이|첫 데이를 만들어 보세요",
            "3|editDaysButton|bottom|데이|데이 이름을 바꾸거나 삭제할 수 있어요",
            "4|settingsButton|bottom|데이|설정과 백업은 여기에서 관리하세요",
            "5|storageSelection|bottom|추가|단어를 저장할 데이를 선택하세요",
            "6|wordInput|bottom|추가|학습할 영단어를 입력하세요",
            "7|pendingWords|top|추가|저장 전에 내용을 확인하세요",
            "8|saveWordsButton|top|추가|확인한 단어를 데이에 저장하세요",
            "9|addHelpButton|bottom|추가|JSON 가져오기는 도움말에서 확인하세요",
            "10|reviewDay|bottom|복습|저장한 단어를 복습하세요",
            "11|editReviewButton|bottom|복습|필요 없는 복습 데이를 정리할 수 있어요",
            "12|studyMemoCollection|bottom|학습 메모|학습 페이지를 다시 열어 보세요",
            "13|createStudyMemoButton|bottom|학습 메모|배운 내용을 학습 메모로 정리하세요"
        ])
    }

    func testSnapshotContractUsesPlatformAppropriateCardScope() {
        let description = VocaDayOnboardingScene.snapshotDescription(
            for: .browseDays,
            sizeName: "검증"
        )

        #if os(macOS)
        XCTAssertTrue(description.contains("cardScope=detail-column"))
        #else
        XCTAssertTrue(description.contains("cardScope=full-screen"))
        #endif
        XCTAssertTrue(description.contains("data=mock-only"))
        XCTAssertTrue(description.contains("interaction=read-only"))
    }

    func testAllStepsRenderAtSupportedLayoutSizes() throws {
        let layouts: [(name: String, width: CGFloat, height: CGFloat)] = [
            ("iPhone SE", 375, 667),
            ("일반 iPhone", 390, 844),
            ("iPhone Pro Max", 440, 956),
            ("Mac", 1_200, 800)
        ]

        for layout in layouts {
            for step in SpotlightStep.allCases {
                let store = OnboardingCompletionStoreSpy()
                let controller = SpotlightFlowController(initialStep: step, completionStore: store)
                let view = VocaDayOnboardingScene(controller: controller)
                    .frame(width: layout.width, height: layout.height)
                    .environment(\.locale, Locale(identifier: "ko_KR"))

                let renderer = ImageRenderer(content: view)
                renderer.scale = 1

                #if os(iOS)
                let image = try XCTUnwrap(renderer.uiImage)
                let data = try XCTUnwrap(image.pngData())
                #else
                let image = try XCTUnwrap(renderer.nsImage)
                let data = try XCTUnwrap(image.tiffRepresentation)
                #endif

                XCTAssertFalse(data.isEmpty, "\(layout.name) · \(step) 렌더 결과가 비어 있습니다.")

                #if os(iOS)
                XCTAssertEqual(image.size.width, layout.width, accuracy: 1)
                XCTAssertEqual(image.size.height, layout.height, accuracy: 1)
                #else
                XCTAssertEqual(image.size.width, layout.width, accuracy: 1)
                XCTAssertEqual(image.size.height, layout.height, accuracy: 1)
                #endif
            }
        }
    }

    func testAccessibilityLargeTextRenders() throws {
        let store = OnboardingCompletionStoreSpy()
        let controller = SpotlightFlowController(initialStep: .enterWord, completionStore: store)
        let view = VocaDayOnboardingScene(controller: controller)
            .frame(width: 375, height: 667)
            .environment(\.dynamicTypeSize, .accessibility3)

        let renderer = ImageRenderer(content: view)
        #if os(iOS)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif
    }

    func testMockFlowDoesNotTouchDatabaseAPIOrSyncAndOnlyPersistsCompletion() throws {
        let store = OnboardingCompletionStoreSpy()
        let controller = SpotlightFlowController(
            initialStep: .browseDays,
            completionStore: store,
            completionKey: "test.onboarding.v1"
        )

        // ModelContainer, ModelContext, 네트워크 및 동기화 의존성 없이 장면 전체가 렌더됩니다.
        let renderer = ImageRenderer(
            content: VocaDayOnboardingScene(controller: controller)
                .frame(width: 390, height: 844)
        )
        #if os(iOS)
        XCTAssertNotNil(renderer.uiImage)
        #else
        XCTAssertNotNil(renderer.nsImage)
        #endif

        for _ in 0..<(SpotlightStep.allCases.count - 1) {
            controller.moveNext()
        }
        controller.moveBack()
        controller.moveNext()

        XCTAssertTrue(store.writes.isEmpty, "단계 이동 중에는 어떤 저장 작업도 없어야 합니다.")

        controller.moveNext()
        XCTAssertEqual(store.writes.count, 1)
        XCTAssertEqual(store.writes.first?.key, "test.onboarding.v1")
        XCTAssertEqual(store.writes.first?.completed, true)
    }

    func testCompletionKeyIsVersioned() {
        XCTAssertEqual(SpotlightOnboardingCompletion.versionedKey, "hasCompletedComponentSpotlightOnboarding_v1")
    }
}

@MainActor
private final class OnboardingCompletionStoreSpy: OnboardingCompletionStoring {
    struct Write: Equatable {
        let completed: Bool
        let key: String
    }

    var writes: [Write] = []

    func isCompleted(forKey key: String) -> Bool {
        writes.last(where: { $0.key == key })?.completed ?? false
    }

    func setCompleted(_ completed: Bool, forKey key: String) {
        writes.append(Write(completed: completed, key: key))
    }
}
