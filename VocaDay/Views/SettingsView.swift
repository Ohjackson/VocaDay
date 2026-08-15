import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var vocabularyDays: [VocabularyDay]
    @Query(sort: \LCDictationDay.createdAt) private var lcDays: [LCDictationDay]
    @Query(sort: \GrammarNote.updatedAt, order: .reverse) private var grammarNotes: [GrammarNote]

    @AppStorage("isJSONImportEnabled") private var isJSONImportEnabled = false
    @State private var showsDeleteConfirmation = false
    @State private var statusMessage: String?

    private var wordCount: Int {
        vocabularyDays.reduce(0) { $0 + $1.wordList.count }
    }

    private var noteCount: Int {
        lcDays.reduce(0) { $0 + $1.noteList.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsIntroduction
                summarySection
                advancedFeaturesSection
                informationSection
                dangerSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("설정")
        .confirmationDialog("모든 앱 데이터를 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("모든 데이터 삭제", role: .destructive) {
                deleteAllData()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장한 데이, 단어, 복습 기록과 학습 노트가 모두 삭제되며 되돌릴 수 없습니다.")
        }
    }

    private var settingsIntroduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VocaDay 설정")
                .font(.title2.weight(.bold))
            Text("필요한 입력 기능을 선택하고, 이 기기에 저장된 학습 데이터를 확인할 수 있습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summarySection: some View {
        settingsSection(title: "데이터 요약") {
            LazyVGrid(columns: summaryColumns, spacing: 12) {
                summaryItem(title: "단어 데이", value: vocabularyDays.count, systemImage: "calendar")
                summaryItem(title: "단어", value: wordCount, systemImage: "textformat.abc")
                summaryItem(title: "LC 노트 묶음", value: lcDays.count, systemImage: "headphones")
                summaryItem(title: "받아쓰기 줄", value: noteCount, systemImage: "note.text")
                summaryItem(title: "문법 노트", value: grammarNotes.count, systemImage: "text.book.closed")
            }
        }
    }

    private var advancedFeaturesSection: some View {
        settingsSection(title: "단어 추가 기능") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isJSONImportEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("외부 AI의 JSON 단어 가져오기")
                            .font(.headline)
                        Text("ChatGPT, Claude, Gemini 같은 외부 AI에서 만든 단어 목록을 ‘추가’ 화면으로 가져옵니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)

                Label {
                    Text(isJSONImportEnabled
                         ? "켜짐: ‘추가’ 화면에 JSON 입력 방식이 표시됩니다."
                         : "꺼짐: ‘추가’ 화면에는 간단한 직접 입력만 표시됩니다.")
                } icon: {
                    Image(systemName: isJSONImportEnabled ? "checkmark.circle.fill" : "info.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("VocaDay 안에는 AI가 내장되어 있지 않으며, 입력한 단어를 외부 AI로 자동 전송하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dangerSection: some View {
        settingsSection(title: "주의") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("모든 앱 데이터 삭제")
                        .font(.headline)
                    Text("단어 데이, 단어, LC 노트, 받아쓰기 줄, 문법 노트를 삭제합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("전체 삭제", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(vocabularyDays.isEmpty && lcDays.isEmpty && grammarNotes.isEmpty)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var informationSection: some View {
        settingsSection(title: "정보") {
            Link(destination: privacyPolicyURL) {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("개인정보 처리방침")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("학습 데이터의 저장, iCloud 동기화와 삭제 방법을 확인합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("웹 브라우저에서 VocaDay 개인정보 처리방침을 엽니다")
        }
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://frequent-silene-a12.notion.site/3bd9fbf6504180a8976af906d35a117f")!
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    private func summaryItem(title: String, value: Int, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func deleteAllData() {
        do {
            try AppDataBackupService.deleteAll(
                in: modelContext,
                vocabularyDays: vocabularyDays,
                lcDays: lcDays,
                grammarNotes: grammarNotes
            )
            statusMessage = "모든 앱 데이터를 삭제했습니다."
        } catch {
            statusMessage = "데이터를 삭제하지 못했습니다. 앱을 다시 연 뒤 시도하세요."
        }
    }
}

private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.headline)
        content()
    }
    .padding(16)
    .calmCard()
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self, LCDictationDay.self, LCDictationNote.self, GrammarNote.self], inMemory: true)
}
