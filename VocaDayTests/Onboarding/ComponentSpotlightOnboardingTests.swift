import XCTest
import SwiftUI
@testable import VocaDay

@MainActor
final class ComponentSpotlightOnboardingTests: XCTestCase {
    func testEveryInstructionalTargetAppearsExactlyOnce() {
        let targets = SpotlightStep.allCases.map(\.target)
        XCTAssertEqual(Set(targets).count, targets.count, "한 대상을 둘 이상의 단계가 설명하면 안 됩니다.")
    }

    func testEveryStepMatchesApprovedSnapshot() {
        let snapshots = SpotlightTour.core.steps.map { step in
            "\(step.rawValue + 1)|\(step.target.rawValue)|\(step.placement.rawValue)|\(step.section.title)|\(step.title)"
        }

        XCTAssertEqual(snapshots, [
            "1|todayWordsBanner|bottom|데이|매일 새 단어 20개로 시작해요",
            "2|studyStatus|bottom|학습|복습 날짜는 앱이 정해요",
            "3|wordInput|bottom|추가|내 단어도 넣을 수 있어요"
        ])
        XCTAssertEqual(SpotlightTour.core.finishTitle, "오늘의 새 단어 고르기")
    }

    func testGatePresentsOnlyToNewUsersUnlessSupervised() {
        XCTAssertEqual(OnboardingGate.decide(cloudCompleted: false, hasExistingData: false, isSupervisedReplay: false), .present)
        guard case .skip = OnboardingGate.decide(cloudCompleted: true, hasExistingData: false, isSupervisedReplay: false) else {
            return XCTFail("다른 기기에서 끝낸 사용자는 건너뛴다.")
        }
        guard case .skip = OnboardingGate.decide(cloudCompleted: false, hasExistingData: true, isSupervisedReplay: false) else {
            return XCTFail("데이가 이미 있는 사용자는 건너뛴다.")
        }
        XCTAssertEqual(OnboardingGate.decide(cloudCompleted: true, hasExistingData: true, isSupervisedReplay: true), .present)
    }

    func testLandingLeadsFinishedUsersIntoTodaysWords() {
        let finished = OnboardingLanding.after(.finished(.core), hasAddedToday: false)
        XCTAssertEqual(finished.section, .days)
        XCTAssertEqual(finished.route, .bundledDayReview)

        let alreadyAdded = OnboardingLanding.after(.finished(.core), hasAddedToday: true)
        XCTAssertEqual(alreadyAdded.section, .exam)
        XCTAssertNil(alreadyAdded.route)

        let skipped = OnboardingLanding.after(.skipped, hasAddedToday: false)
        XCTAssertEqual(skipped.section, .days)
        XCTAssertNil(skipped.route)
    }

    func testCompletionStoreTreatsEitherRecordAsCompleted() throws {
        let suite = "test.onboarding.store.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "test.onboarding.completion.\(UUID().uuidString)"
        let store = UbiquitousOnboardingCompletionStore(defaults: defaults)
        defer { NSUbiquitousKeyValueStore.default.removeObject(forKey: key) }

        XCTAssertFalse(store.isCompleted(forKey: key))
        store.setCompleted(true, forKey: key)
        XCTAssertTrue(defaults.bool(forKey: key))
        XCTAssertTrue(NSUbiquitousKeyValueStore.default.bool(forKey: key))

        defaults.set(false, forKey: key)
        XCTAssertTrue(store.isCompleted(forKey: key), "이 기기 기록이 없어도 iCloud 기록이 있으면 완료다.")
    }

    func testSnapshotContractUsesPlatformAppropriateCardScope() {
        let description = VocaDayOnboardingScene.snapshotDescription(
            for: .dailyWords,
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
        #if os(iOS)
        let layouts: [(name: String, width: CGFloat, height: CGFloat)] = [
            ("iPhone SE", 375, 667),
            ("일반 iPhone", 390, 844),
            ("iPhone Pro Max", 440, 956)
        ]
        #else
        let layouts: [(name: String, width: CGFloat, height: CGFloat)] = [
            ("Mac 최소 창", 760, 560),
            ("Mac 넓은 창", 1_440, 900)
        ]
        #endif

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

    func testLightAndDarkAppearanceVariantsRender() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            let store = OnboardingCompletionStoreSpy()
            let controller = SpotlightFlowController(initialStep: .saveWords, completionStore: store)
            let view = VocaDayOnboardingScene(controller: controller)
                .frame(width: 760, height: 560)
                .environment(\.colorScheme, colorScheme)

            let renderer = ImageRenderer(content: view)
            #if os(iOS)
            XCTAssertNotNil(renderer.uiImage)
            #else
            XCTAssertNotNil(renderer.nsImage)
            #endif
        }
    }

    func testMockFlowDoesNotTouchDatabaseAPIOrSyncAndOnlyPersistsCompletion() throws {
        let store = OnboardingCompletionStoreSpy()
        let controller = SpotlightFlowController(
            initialStep: .dailyWords,
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

        for _ in 0..<(controller.steps.count - 1) {
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

    func testFullTourCoversEveryStepOnceAndCoreIsItsSubset() {
        XCTAssertEqual(Set(SpotlightTour.full.steps), Set(SpotlightStep.allCases))
        XCTAssertEqual(SpotlightTour.full.steps.count, SpotlightStep.allCases.count)
        XCTAssertTrue(Set(SpotlightTour.core.steps).isSubset(of: Set(SpotlightTour.full.steps)))
    }

    func testControllerWalksTheChosenTourInOrder() {
        let store = OnboardingCompletionStoreSpy()
        let controller = SpotlightFlowController(initialStep: .dailyWords, tour: .full, completionStore: store)
        var visited = [controller.currentStep]
        while !controller.isLastStep {
            controller.moveNext()
            visited.append(controller.currentStep)
        }
        XCTAssertEqual(visited, SpotlightTour.full.steps)

        let jumped = SpotlightFlowController(initialStep: .openSettings, completionStore: store)
        XCTAssertEqual(jumped.tour, .full, "핵심 절차에 없는 단계는 전체 절차로 보여 준다.")
        XCTAssertEqual(jumped.stepNumber, SpotlightTour.full.steps.firstIndex(of: .openSettings)! + 1)
    }

    func testCompletionKeyIsVersioned() {
        XCTAssertEqual(SpotlightOnboardingCompletion.versionedKey, "hasCompletedComponentSpotlightOnboarding_v3")
    }

    func testOnboardingSourceDoesNotUseCoordinateOrCutoutTechniques() throws {
        let sourceRoot = try onboardingSourceRoot()
        let forbiddenTokens = [
            "GeometryReader", "frame(in:", "PreferenceKey", "AnchorPreference",
            "convert(", "Canvas", "mask(", "blendMode(.destinationOut"
        ]

        let files = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let source = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        for token in forbiddenTokens {
            XCTAssertFalse(source.contains(token), "온보딩 소스에서 금지 API를 발견했습니다: \(token)")
        }
    }

    func testMockSceneHasNoPersistenceNetworkNotificationOrTimerDependencies() throws {
        let sceneURL = try onboardingSourceRoot().appendingPathComponent("VocaDayOnboardingScene.swift")
        let source = try String(contentsOf: sceneURL, encoding: .utf8)
        let forbiddenTokens = [
            "ModelContext", "ModelContainer", "@Query", "URLSession",
            "UNUserNotificationCenter", "ActivityKit", "Timer.", "UserDefaults"
        ]

        for token in forbiddenTokens {
            XCTAssertFalse(source.contains(token), "Mock 장면이 외부 상태에 접근합니다: \(token)")
        }
    }

    private func onboardingSourceRoot() throws -> URL {
        let testsURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = projectRoot.appendingPathComponent("VocaDay/Onboarding", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceRoot.path))
        return sourceRoot
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
