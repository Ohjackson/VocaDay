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
        let snapshots = SpotlightStep.allCases.map { step in
            "\(step.rawValue + 1)|\(step.target.rawValue)|\(step.placement.rawValue)|\(step.section.title)|\(step.title)"
        }

        XCTAssertEqual(snapshots, [
            "1|dayCollection|bottom|데이|단어를 데이별로 모아요",
            "2|wordInput|bottom|추가|원하는 방식으로 단어를 추가해요",
            "3|saveWordsButton|top|추가|확인한 내용만 저장해요",
            "4|reviewDay|bottom|복습|기억하면서 복습해요"
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
