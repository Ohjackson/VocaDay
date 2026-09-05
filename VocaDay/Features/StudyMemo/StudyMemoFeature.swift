import SwiftData
import SwiftUI

/// 다른 화면이나 앱에서 학습 메모 기능을 붙일 때 사용하는 진입점입니다.
///
/// 호스트 앱의 `ModelContainer`에는 `StudyMemo`와 `StudyPageCategory`를
/// 반드시 포함해야 합니다.
struct StudyMemoFeatureView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyMemo.updatedAt, order: .reverse) private var memos: [StudyMemo]

    private let includesDemoData: Bool

    init(includesDemoData: Bool = true) {
        self.includesDemoData = includesDemoData
    }

    var body: some View {
        StudyMemosView()
            .task {
                guard includesDemoData else { return }
                StudyMemoDemoSeeder.seedIfNeeded(
                    existingMemos: memos,
                    in: modelContext
                )
            }
    }
}
