import XCTest
@testable import VocaDay

/// macOS에서 사이드바는 ‘학습 메모’인데 본문은 이전 섹션의 복습 화면이 남던 문제의 재발을 막습니다.
///
/// 원인: 섹션 스택을 `NavigationStack { … }.id(section)` 으로 만들고 `NavigationLink { 목적지 }`
/// 로 화면을 쌓았습니다. 이렇게 쌓인 화면은 경로(path)에 없어서 섹션을 바꿔도 비울 방법이 없고,
/// NavigationSplitView 의 detail 열이 그 화면을 그대로 유지했습니다.
/// 해결: 모든 push 를 `AppRoute` 경로로 표현하고, 섹션 선택과 경로를 `AppNavigationState` 한곳에서 바꿉니다.
@MainActor
final class NavigationArchitectureTests: XCTestCase {
    func testMacSectionChangeClearsEveryStack() {
        var state = AppNavigationState(selectedSection: .review)
        state.push(.reviewSession(dayID: UUID(), dueOnly: true))
        state.select(.studyMemos, policy: .resetAllStacks)

        XCTAssertEqual(state.selectedSection, .studyMemos)
        for section in AppSection.allCases {
            XCTAssertTrue(state.path(for: section).isEmpty, "\(section) 스택이 남아 있습니다.")
        }
    }

    func testTabChangeKeepsEachTabStack() {
        let dayID = UUID()
        var state = AppNavigationState(selectedSection: .review)
        state.push(.reviewSession(dayID: dayID, dueOnly: false))
        state.select(.days, policy: .keepStacks)
        state.push(.settings)

        XCTAssertEqual(state.path(for: .review), [.reviewSession(dayID: dayID, dueOnly: false)])
        XCTAssertEqual(state.path(for: .days), [.settings])

        state.pop()
        XCTAssertTrue(state.path(for: .days).isEmpty)
    }

    /// 경로 밖에서 화면을 쌓는 API 를 쓰면 실패합니다. 새 화면은 `AppRoute` 에 case 를 추가하세요.
    func testSourcesUseOnlyValueBasedNavigation() throws {
        let forbidden: [(pattern: String, reason: String)] = [
            (#"NavigationLink\s*\{"#, "NavigationLink { 목적지 } 대신 NavigationLink(value: AppRoute.…)"),
            (#"NavigationLink\s*\([^)]*destination:"#, "NavigationLink(destination:) 대신 NavigationLink(value:)"),
            (#"navigationDestination\s*\(\s*(item|isPresented):"#, "navigationDestination(item:/isPresented:) 대신 AppRoute + appNavigate"),
            (#"NavigationStack\s*\{[^}]*\}\s*\.id\("#, "NavigationStack 을 .id() 로 다시 만들지 말고 경로를 비우세요"),
        ]

        var violations: [String] = []
        for fileURL in try swiftSources() {
            // 주석은 검사하지 않습니다. 줄 번호를 유지하려고 빈 줄로 바꿉니다.
            let source = try String(contentsOf: fileURL, encoding: .utf8)
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : $0 }
                .joined(separator: "\n")
            for rule in forbidden {
                let regex = try NSRegularExpression(pattern: rule.pattern)
                let range = NSRange(source.startIndex..., in: source)
                for match in regex.matches(in: source, range: range) {
                    let line = source[..<Range(match.range, in: source)!.lowerBound].filter { $0 == "\n" }.count + 1
                    violations.append("\(fileURL.lastPathComponent):\(line) — \(rule.reason)")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, "\n" + violations.joined(separator: "\n"))
    }

    private func swiftSources() throws -> [URL] {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VocaDay", isDirectory: true)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "소스 폴더를 찾지 못했습니다: \(appRoot.path)")
        return files
    }
}
