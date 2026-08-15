import SwiftData
import SwiftUI

private enum SettingsExportScope: String, CaseIterable, Identifiable {
    case all = "all"
    case vocabularyDay = "vocabularyDay"
    case lcDictationDay = "lcDictationDay"
    case grammarNote = "grammarNote"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "전체 앱 데이터"
        case .vocabularyDay:
            return "단어 데이"
        case .lcDictationDay:
            return "LC 노트"
        case .grammarNote:
            return "문법 노트"
        }
    }
}

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
                summarySection
                advancedFeaturesSection
                if isJSONImportEnabled {
                    dataManagementSection
                }
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
            Text("이 기기와 동기화된 SwiftData 저장소에서 단어와 학습 데이터를 모두 삭제합니다.")
        }
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

    private var dataManagementSection: some View {
        settingsSection(title: "데이터") {
            NavigationLink {
                AppDataManagementView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.arrow.down.doc")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("데이터 관리")
                            .font(.headline)
                        Text("전체 데이터 또는 선택한 데이의 JSON을 복사, 붙여넣기, 미리 보기, 적용할 수 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var advancedFeaturesSection: some View {
        settingsSection(title: "고급 기능") {
            Toggle(isOn: $isJSONImportEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("JSON 기능 사용")
                        .font(.headline)
                    Text("단어 추가 화면의 JSON 가져오기와 설정의 JSON 데이터 관리 메뉴를 표시합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
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
            statusMessage = "삭제 실패: \(error.localizedDescription)"
        }
    }
}

private struct AppDataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var vocabularyDays: [VocabularyDay]
    @Query(sort: \LCDictationDay.createdAt) private var lcDays: [LCDictationDay]
    @Query(sort: \GrammarNote.updatedAt, order: .reverse) private var grammarNotes: [GrammarNote]

    @State private var exportScope: SettingsExportScope = .all
    @State private var selectedVocabularyDayID: UUID?
    @State private var selectedLCDayID: UUID?
    @State private var selectedGrammarNoteID: UUID?
    @State private var jsonText = ""
    @State private var statusMessage: String?
    @State private var previewSummary: String?
    @State private var pendingArchive: AppDataArchive?
    @State private var showsApplyConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                exportSection
                jsonSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("데이터 관리")
        .onAppear {
            syncDefaultSelections()
        }
        .onChange(of: vocabularyDays.map(\.id)) { _, _ in
            syncDefaultSelections()
        }
        .onChange(of: lcDays.map(\.id)) { _, _ in
            syncDefaultSelections()
        }
        .onChange(of: grammarNotes.map(\.id)) { _, _ in
            syncDefaultSelections()
        }
        .onChange(of: jsonText) { _, _ in
            pendingArchive = nil
            previewSummary = nil
        }
        .confirmationDialog("가져온 JSON을 적용할까요?", isPresented: $showsApplyConfirmation) {
            Button("변경 사항 적용") {
                applyPendingArchive()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(previewSummary ?? "일치하는 저장 데이터를 업데이트하고 없는 항목은 새로 만듭니다.")
        }
    }

    private var exportSection: some View {
        settingsSection(title: "내보내기 범위") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("범위", selection: $exportScope) {
                    ForEach(SettingsExportScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if exportScope == .vocabularyDay {
                    Picker("데이", selection: vocabularyDaySelection) {
                        ForEach(vocabularyDays) { day in
                            Text(day.title).tag(day.id)
                        }
                    }
                    .disabled(vocabularyDays.isEmpty)
                }

                if exportScope == .lcDictationDay {
                    Picker("LC 노트", selection: lcDaySelection) {
                        ForEach(lcDays) { day in
                            Text(day.title).tag(day.id)
                        }
                    }
                    .disabled(lcDays.isEmpty)
                }

                if exportScope == .grammarNote {
                    Picker("문법 노트", selection: grammarNoteSelection) {
                        ForEach(grammarNotes) { note in
                            Text(note.title).tag(note.id)
                        }
                    }
                    .disabled(grammarNotes.isEmpty)
                }

                HStack {
                    Button {
                        copyCurrentJSON()
                    } label: {
                        Label("JSON 복사", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCopyCurrentScope)

                    Button {
                        pasteJSON()
                    } label: {
                        Label("JSON 붙여넣기", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private var jsonSection: some View {
        settingsSection(title: "JSON 작업") {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $jsonText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 240)
                    .padding(8)
                    .background(AppTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.softStroke)
                    }

                HStack {
                    Button {
                        previewJSON()
                    } label: {
                        Label("변경 사항 미리 보기", systemImage: "list.bullet.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        if pendingArchive == nil {
                            previewJSON()
                        }
                        if pendingArchive != nil {
                            showsApplyConfirmation = true
                        }
                    } label: {
                        Label("변경 사항 적용", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                if let previewSummary {
                    Text(previewSummary)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var vocabularyDaySelection: Binding<UUID> {
        Binding {
            selectedVocabularyDayID ?? vocabularyDays.first?.id ?? UUID()
        } set: { newValue in
            selectedVocabularyDayID = newValue
        }
    }

    private var lcDaySelection: Binding<UUID> {
        Binding {
            selectedLCDayID ?? lcDays.first?.id ?? UUID()
        } set: { newValue in
            selectedLCDayID = newValue
        }
    }

    private var grammarNoteSelection: Binding<UUID> {
        Binding {
            selectedGrammarNoteID ?? grammarNotes.first?.id ?? UUID()
        } set: { newValue in
            selectedGrammarNoteID = newValue
        }
    }

    private var canCopyCurrentScope: Bool {
        switch exportScope {
        case .all:
            return true
        case .vocabularyDay:
            return selectedVocabularyDay != nil
        case .lcDictationDay:
            return selectedLCDay != nil
        case .grammarNote:
            return selectedGrammarNote != nil
        }
    }

    private var selectedVocabularyDay: VocabularyDay? {
        guard let selectedVocabularyDayID else { return vocabularyDays.first }
        return vocabularyDays.first { $0.id == selectedVocabularyDayID }
    }

    private var selectedLCDay: LCDictationDay? {
        guard let selectedLCDayID else { return lcDays.first }
        return lcDays.first { $0.id == selectedLCDayID }
    }

    private var selectedGrammarNote: GrammarNote? {
        guard let selectedGrammarNoteID else { return grammarNotes.first }
        return grammarNotes.first { $0.id == selectedGrammarNoteID }
    }

    private func syncDefaultSelections() {
        if selectedVocabularyDayID == nil || !vocabularyDays.contains(where: { $0.id == selectedVocabularyDayID }) {
            selectedVocabularyDayID = vocabularyDays.first?.id
        }

        if selectedLCDayID == nil || !lcDays.contains(where: { $0.id == selectedLCDayID }) {
            selectedLCDayID = lcDays.first?.id
        }

        if selectedGrammarNoteID == nil || !grammarNotes.contains(where: { $0.id == selectedGrammarNoteID }) {
            selectedGrammarNoteID = grammarNotes.first?.id
        }
    }

    private func makeArchiveForCurrentScope() -> AppDataArchive? {
        switch exportScope {
        case .all:
            return AppDataBackupService.archiveAll(vocabularyDays: vocabularyDays, lcDays: lcDays, grammarNotes: grammarNotes)
        case .vocabularyDay:
            guard let selectedVocabularyDay else { return nil }
            return AppDataBackupService.archiveVocabularyDay(selectedVocabularyDay)
        case .lcDictationDay:
            guard let selectedLCDay else { return nil }
            return AppDataBackupService.archiveLCDictationDay(selectedLCDay)
        case .grammarNote:
            guard let selectedGrammarNote else { return nil }
            return AppDataBackupService.archiveGrammarNote(selectedGrammarNote)
        }
    }

    private func copyCurrentJSON() {
        guard let archive = makeArchiveForCurrentScope() else {
            statusMessage = "JSON을 복사할 데이를 선택하세요."
            return
        }

        do {
            let json = try AppDataBackupService.encode(archive)
            ClipboardService.copyText(json)
            jsonText = json
            statusMessage = "JSON을 복사했습니다."
        } catch {
            statusMessage = "복사 실패: \(error.localizedDescription)"
        }
    }

    private func pasteJSON() {
        guard let clipboardText = ClipboardService.readText(),
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "클립보드가 비어 있습니다."
            return
        }

        jsonText = clipboardText
        statusMessage = "JSON을 붙여넣었습니다."
    }

    private func previewJSON() {
        do {
            let archive = try AppDataBackupService.decode(jsonText)
            let preview = AppDataBackupService.preview(
                archive,
                vocabularyDays: vocabularyDays,
                lcDays: lcDays,
                grammarNotes: grammarNotes
            )
            pendingArchive = archive
            previewSummary = preview.summary
            statusMessage = "미리 보기를 준비했습니다."
        } catch {
            pendingArchive = nil
            previewSummary = nil
            statusMessage = "잘못된 JSON: \(error.localizedDescription)"
        }
    }

    private func applyPendingArchive() {
        guard let pendingArchive else {
            statusMessage = "적용하기 전에 JSON을 미리 보세요."
            return
        }

        do {
            try AppDataBackupService.applyUpsert(
                pendingArchive,
                in: modelContext,
                vocabularyDays: vocabularyDays,
                lcDays: lcDays,
                grammarNotes: grammarNotes
            )
            statusMessage = "변경 사항을 적용했습니다."
            previewSummary = nil
            self.pendingArchive = nil
        } catch {
            statusMessage = "적용 실패: \(error.localizedDescription)"
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
