import SwiftData
import SwiftUI

/// 기본 단어 검수에서 "이미 알아요"로 보관한 단어. 되돌리면 다시 오늘의 새 단어 후보가 된다.
struct SetAsideWordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SetAsideWord.createdAt, order: .reverse) private var words: [SetAsideWord]

    @State private var errorAlert: VocaAlert?

    var body: some View {
        AppCollectionPage(maxContentWidth: 640, horizontalPadding: 20, verticalPadding: 24) {
            if words.isEmpty {
                EmptyStateView(title: "보관한 단어가 없어요.", systemImage: "archivebox")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("단어장에 넣지 않은 단어 \(words.count)개. 되돌리면 다음 새 단어 후보로 다시 나와요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                            if index > 0 {
                                Divider()
                            }
                            row(word)
                        }
                    }
                    .padding(.horizontal, AppTheme.cardPadding)
                    .calmCard()
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle("보관함")
        .alert(item: $errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private func row(_ word: SetAsideWord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.english)
                    .font(.body.weight(.semibold))
                Text(word.meaningKo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(word.createdAt, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("되돌리기", systemImage: "arrow.uturn.backward") {
                restore(word)
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
            .accessibilityLabel("\(word.english) 되돌리기")
        }
        .padding(.vertical, 10)
    }

    private func restore(_ word: SetAsideWord) {
        // 다른 기기에서 같은 단어가 따로 보관됐을 수 있으니 같은 철자는 함께 지운다.
        let key = word.english.normalizedEnglish
        for item in words where item.english.normalizedEnglish == key {
            modelContext.delete(item)
        }
        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
        }
    }
}
