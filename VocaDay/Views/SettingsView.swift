import SwiftData
import SwiftUI

private enum SettingsExportScope: String, CaseIterable, Identifiable {
    case all = "All App Data"
    case vocabularyDay = "Vocabulary Day"
    case lcDictationDay = "LC Note"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all:
            return "All App Data"
        case .vocabularyDay:
            return "Vocabulary Day"
        case .lcDictationDay:
            return "LC Note"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var vocabularyDays: [VocabularyDay]
    @Query(sort: \LCDictationDay.createdAt) private var lcDays: [LCDictationDay]

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
                dataManagementSection
                dangerSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("Settings")
        .confirmationDialog("Delete all app data?", isPresented: $showsDeleteConfirmation) {
            Button("Delete All Data", role: .destructive) {
                deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all Vocabulary and Study data from this device and synced SwiftData store.")
        }
    }

    private var summarySection: some View {
        settingsSection(title: "Data Summary") {
            LazyVGrid(columns: summaryColumns, spacing: 12) {
                summaryItem(title: "Vocabulary Days", value: vocabularyDays.count, systemImage: "calendar")
                summaryItem(title: "Words", value: wordCount, systemImage: "textformat.abc")
                summaryItem(title: "LC Note Groups", value: lcDays.count, systemImage: "headphones")
                summaryItem(title: "Dictation Lines", value: noteCount, systemImage: "note.text")
            }
        }
    }

    private var dataManagementSection: some View {
        settingsSection(title: "Data") {
            NavigationLink {
                AppDataManagementView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.arrow.down.doc")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Data Management")
                            .font(.headline)
                        Text("Copy, paste, preview, and apply JSON for all data or a selected Day.")
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

    private var dangerSection: some View {
        settingsSection(title: "Danger Zone") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delete all app data")
                        .font(.headline)
                    Text("Removes Vocabulary Days, Words, LC Notes, and dictation lines.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(vocabularyDays.isEmpty && lcDays.isEmpty)
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

    private func summaryItem(title: LocalizedStringKey, value: Int, systemImage: String) -> some View {
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
            try AppDataBackupService.deleteAll(in: modelContext, vocabularyDays: vocabularyDays, lcDays: lcDays)
            statusMessage = String(localized: "All app data deleted.")
        } catch {
            statusMessage = String(format: String(localized: "Delete failed: %@"), error.localizedDescription)
        }
    }
}

private struct AppDataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var vocabularyDays: [VocabularyDay]
    @Query(sort: \LCDictationDay.createdAt) private var lcDays: [LCDictationDay]

    @State private var exportScope: SettingsExportScope = .all
    @State private var selectedVocabularyDayID: UUID?
    @State private var selectedLCDayID: UUID?
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
        .navigationTitle("Data Management")
        .onAppear {
            syncDefaultSelections()
        }
        .onChange(of: vocabularyDays.map(\.id)) { _, _ in
            syncDefaultSelections()
        }
        .onChange(of: lcDays.map(\.id)) { _, _ in
            syncDefaultSelections()
        }
        .onChange(of: jsonText) { _, _ in
            pendingArchive = nil
            previewSummary = nil
        }
        .confirmationDialog("Apply imported JSON?", isPresented: $showsApplyConfirmation) {
            Button("Apply Changes") {
                applyPendingArchive()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(previewSummary ?? "This updates matching saved data and creates missing items.")
        }
    }

    private var exportSection: some View {
        settingsSection(title: "Export Scope") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Scope", selection: $exportScope) {
                    ForEach(SettingsExportScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if exportScope == .vocabularyDay {
                    Picker("Day", selection: vocabularyDaySelection) {
                        ForEach(vocabularyDays) { day in
                            Text(day.title).tag(day.id)
                        }
                    }
                    .disabled(vocabularyDays.isEmpty)
                }

                if exportScope == .lcDictationDay {
                    Picker("LC Note", selection: lcDaySelection) {
                        ForEach(lcDays) { day in
                            Text(day.title).tag(day.id)
                        }
                    }
                    .disabled(lcDays.isEmpty)
                }

                HStack {
                    Button {
                        copyCurrentJSON()
                    } label: {
                        Label("Copy JSON", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCopyCurrentScope)

                    Button {
                        pasteJSON()
                    } label: {
                        Label("Paste JSON", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private var jsonSection: some View {
        settingsSection(title: "JSON Actions") {
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
                        Label("Preview Changes", systemImage: "list.bullet.clipboard")
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
                        Label("Apply Changes", systemImage: "checkmark.circle")
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

    private var canCopyCurrentScope: Bool {
        switch exportScope {
        case .all:
            return true
        case .vocabularyDay:
            return selectedVocabularyDay != nil
        case .lcDictationDay:
            return selectedLCDay != nil
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

    private func syncDefaultSelections() {
        if selectedVocabularyDayID == nil || !vocabularyDays.contains(where: { $0.id == selectedVocabularyDayID }) {
            selectedVocabularyDayID = vocabularyDays.first?.id
        }

        if selectedLCDayID == nil || !lcDays.contains(where: { $0.id == selectedLCDayID }) {
            selectedLCDayID = lcDays.first?.id
        }
    }

    private func makeArchiveForCurrentScope() -> AppDataArchive? {
        switch exportScope {
        case .all:
            return AppDataBackupService.archiveAll(vocabularyDays: vocabularyDays, lcDays: lcDays)
        case .vocabularyDay:
            guard let selectedVocabularyDay else { return nil }
            return AppDataBackupService.archiveVocabularyDay(selectedVocabularyDay)
        case .lcDictationDay:
            guard let selectedLCDay else { return nil }
            return AppDataBackupService.archiveLCDictationDay(selectedLCDay)
        }
    }

    private func copyCurrentJSON() {
        guard let archive = makeArchiveForCurrentScope() else {
            statusMessage = String(localized: "Select a Day before copying JSON.")
            return
        }

        do {
            let json = try AppDataBackupService.encode(archive)
            ClipboardService.copyText(json)
            jsonText = json
            statusMessage = String(localized: "JSON copied.")
        } catch {
            statusMessage = String(format: String(localized: "Copy failed: %@"), error.localizedDescription)
        }
    }

    private func pasteJSON() {
        guard let clipboardText = ClipboardService.readText(),
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = String(localized: "Clipboard is empty.")
            return
        }

        jsonText = clipboardText
        statusMessage = String(localized: "JSON pasted.")
    }

    private func previewJSON() {
        do {
            let archive = try AppDataBackupService.decode(jsonText)
            let preview = AppDataBackupService.preview(archive, vocabularyDays: vocabularyDays, lcDays: lcDays)
            pendingArchive = archive
            previewSummary = preview.summary
            statusMessage = String(localized: "Preview ready.")
        } catch {
            pendingArchive = nil
            previewSummary = nil
            statusMessage = String(format: String(localized: "Invalid JSON: %@"), error.localizedDescription)
        }
    }

    private func applyPendingArchive() {
        guard let pendingArchive else {
            statusMessage = String(localized: "Preview the JSON before applying it.")
            return
        }

        do {
            try AppDataBackupService.applyUpsert(
                pendingArchive,
                in: modelContext,
                vocabularyDays: vocabularyDays,
                lcDays: lcDays
            )
            statusMessage = String(localized: "Changes applied.")
            previewSummary = nil
            self.pendingArchive = nil
        } catch {
            statusMessage = String(format: String(localized: "Apply failed: %@"), error.localizedDescription)
        }
    }
}

private func settingsSection<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
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
    .modelContainer(for: [VocabularyDay.self, VocaWord.self, LCDictationDay.self, LCDictationNote.self], inMemory: true)
}
