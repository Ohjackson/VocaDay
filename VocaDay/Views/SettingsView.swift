import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum BackupMethod: String, CaseIterable, Identifiable {
    case iCloudSync
    case jsonFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloudSync: "iCloud"
        case .jsonFile: "JSON 파일"
        }
    }
}

private enum BackupExportScope: String, CaseIterable, Identifiable {
    case allData
    case vocabularyDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allData: "전체 백업"
        case .vocabularyDay: "데이 선택"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var vocabularyDays: [VocabularyDay]
    @Query(sort: \LCDictationDay.createdAt) private var lcDays: [LCDictationDay]
    @Query(sort: \GrammarNote.updatedAt, order: .reverse) private var grammarNotes: [GrammarNote]
    @Query(sort: \CustomStudyPage.updatedAt, order: .reverse) private var customStudyPages: [CustomStudyPage]

    @AppStorage("isJSONImportEnabled") private var isJSONImportEnabled = false
    @AppStorage("lastSuccessfulBackupAt") private var lastSuccessfulBackupAt = 0.0
    @AppStorage("hasCompletedSpotlightOnboarding") private var hasCompletedSpotlightOnboarding = false
    @State private var showsDeleteConfirmation = false
    @State private var statusMessage: String?
    @State private var backupStatusMessage: String?
    @State private var backupDocument = VocaDayBackupDocument()
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingRestoreArchive: AppDataArchive?
    @State private var restoreSummary = ""
    @State private var showsRestoreConfirmation = false
    @AppStorage("preferredBackupMethod") private var backupMethod: BackupMethod = .iCloudSync
    @AppStorage("preferredBackupExportScope") private var backupExportScope: BackupExportScope = .allData
    @State private var selectedBackupDayID: UUID?

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
                backupSection
                advancedFeaturesSection
                usageGuideSection
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
        .confirmationDialog("백업 데이터를 복원할까요?", isPresented: $showsRestoreConfirmation, titleVisibility: .visible) {
            Button("현재 데이터와 병합") {
                restorePendingBackup()
            }
            Button("취소", role: .cancel) {
                pendingRestoreArchive = nil
            }
        } message: {
            Text("\(restoreSummary)\n\n현재 데이터는 먼저 삭제하지 않습니다. 같은 항목은 백업 내용으로 업데이트하고, 없는 항목은 새로 추가합니다.")
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: backupFilename
        ) { result in
            switch result {
            case .success:
                lastSuccessfulBackupAt = Date().timeIntervalSince1970
                backupStatusMessage = "백업 파일을 저장했습니다."
            case .failure(let error):
                if !isUserCancellation(error) {
                    backupStatusMessage = "백업 파일을 저장하지 못했습니다: \(error.localizedDescription)"
                }
            }
        }
        .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            importBackup(result)
        }
        .onAppear(perform: ensureSelectedBackupDay)
        .onChange(of: vocabularyDays.map(\.id)) { _, _ in
            ensureSelectedBackupDay()
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
                summaryItem(title: "내 학습 페이지", value: customStudyPages.count, systemImage: "square.grid.2x2")
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

    private var backupSection: some View {
        settingsSection(title: "백업 및 복원") {
            VStack(alignment: .leading, spacing: 14) {
                Text("자동 동기화 상태를 확인하거나, 원하는 시점의 데이터를 복원 가능한 파일로 따로 보관하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("저장 방식", selection: $backupMethod) {
                    ForEach(BackupMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if backupMethod == .iCloudSync {
                    iCloudBackupExplanation
                } else {
                    jsonFileBackupControls
                }
            }
        }
    }

    private var iCloudBackupExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("iCloud 자동 동기화", systemImage: "icloud")
                .font(.headline)
                .foregroundStyle(Color.accentColor)

            Text("기기에 Apple 계정이 로그인되어 있고 VocaDay의 iCloud 사용이 허용되면 단어와 학습 노트가 개인 CloudKit 저장소를 통해 자동으로 동기화됩니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("동기화는 백업 파일이 아닙니다", systemImage: "exclamationmark.circle")
                .font(.caption.weight(.semibold))

            Text("한 기기에서 삭제한 내용도 다른 기기에 반영될 수 있습니다. 특정 시점으로 되돌릴 파일이 필요하면 ‘JSON 파일’을 선택해 별도로 저장하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppTheme.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous))
    }

    private var jsonFileBackupControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("학습 데이터를 사람이 읽을 수 있는 JSON 텍스트 파일로 저장합니다. 파일 앱에서 ‘나의 iPhone’이나 iCloud Drive 등 원하는 위치를 선택할 수 있습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("백업 범위", selection: $backupExportScope) {
                ForEach(BackupExportScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            if backupExportScope == .vocabularyDay {
                if vocabularyDays.isEmpty {
                    Label("백업할 단어 데이가 없습니다.", systemImage: "calendar.badge.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("백업할 데이", selection: $selectedBackupDayID) {
                        ForEach(vocabularyDays) { day in
                            Text("\(day.title) · \(day.wordList.count)단어")
                                .tag(Optional(day.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            } else {
                Label("단어와 복습 기록, LC·문법 노트, 직접 만든 학습 페이지를 모두 포함합니다.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button {
                    prepareBackup()
                } label: {
                    Label(backupExportScope == .allData ? "전체 백업 파일 저장" : "선택한 데이 백업", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasExportableBackupData)

                Button {
                    isImportingBackup = true
                } label: {
                    Label("JSON 백업에서 복원", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if !hasExportableBackupData {
                Text(backupExportScope == .allData
                     ? "저장된 학습 데이터가 없어 아직 전체 백업을 만들 수 없습니다."
                     : "백업할 데이를 먼저 선택하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if lastSuccessfulBackupAt > 0 {
                Label("마지막 파일 백업: \(Date(timeIntervalSince1970: lastSuccessfulBackupAt).formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let backupStatusMessage {
                Text(backupStatusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("JSON 파일에는 입력한 학습 내용이 그대로 들어 있습니다. 공유 기기나 공개 폴더에는 저장하지 마세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dangerSection: some View {
        settingsSection(title: "주의") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("모든 앱 데이터 삭제")
                        .font(.headline)
                    Text("단어, LC·문법 노트와 직접 만든 학습 페이지를 모두 삭제합니다.")
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
                .disabled(vocabularyDays.isEmpty && lcDays.isEmpty && grammarNotes.isEmpty && customStudyPages.isEmpty)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var usageGuideSection: some View {
        settingsSection(title: "사용 안내") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text("스포트라이트 안내 다시 보기")
                        .font(.headline)
                    Text("주요 화면의 실제 버튼과 영역을 밝게 강조하며 사용 순서를 다시 안내합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button("시작") {
                    hasCompletedSpotlightOnboarding = false
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var informationSection: some View {
        settingsSection(title: "개인정보 및 서비스 안내") {
            VStack(spacing: 0) {
                serviceStatusRow(
                    title: "회원가입·로그인 없음",
                    description: "VocaDay 계정을 만들지 않습니다. iCloud 동기화는 기기에 로그인된 Apple 계정을 사용합니다.",
                    systemImage: "person.crop.circle.badge.xmark"
                )

                Divider()
                    .padding(.leading, 52)

                serviceStatusRow(
                    title: "결제·구독 없음",
                    description: "인앱 결제나 유료 구독 없이 모든 기능을 사용할 수 있습니다.",
                    systemImage: "creditcard"
                )

                Divider()
                    .padding(.leading, 52)

                serviceStatusRow(
                    title: "광고·사용자 추적 없음",
                    description: "광고를 표시하지 않으며 광고 식별자나 앱 사용 행동을 추적하지 않습니다.",
                    systemImage: "eye.slash"
                )
            }
            .background(AppTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous))

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
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("웹 브라우저에서 VocaDay 개인정보 처리방침을 엽니다")
        }
    }

    private func serviceStatusRow(title: String, description: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://frequent-silene-a12.notion.site/3bd9fbf6504180a8976af906d35a117f")!
    }

    private var hasBackupData: Bool {
        !vocabularyDays.isEmpty || !lcDays.isEmpty || !grammarNotes.isEmpty || !customStudyPages.isEmpty
    }

    private var selectedBackupDay: VocabularyDay? {
        guard let selectedBackupDayID else { return nil }
        return vocabularyDays.first { $0.id == selectedBackupDayID }
    }

    private var hasExportableBackupData: Bool {
        switch backupExportScope {
        case .allData: hasBackupData
        case .vocabularyDay: selectedBackupDay != nil
        }
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        if backupExportScope == .vocabularyDay, let selectedBackupDay {
            let safeTitle = selectedBackupDay.title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            return "VocaDay-\(safeTitle)-\(date)"
        }
        return "VocaDay-전체-\(date)"
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
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous))
    }

    private func deleteAllData() {
        do {
            try AppDataBackupService.deleteAll(
                in: modelContext,
                vocabularyDays: vocabularyDays,
                lcDays: lcDays,
                grammarNotes: grammarNotes,
                customStudyPages: customStudyPages
            )
            statusMessage = "모든 앱 데이터를 삭제했습니다."
        } catch {
            statusMessage = "데이터를 삭제하지 못했습니다. 앱을 다시 연 뒤 시도하세요."
        }
    }

    private func prepareBackup() {
        do {
            let archive: AppDataArchive
            switch backupExportScope {
            case .allData:
                archive = AppDataBackupService.archiveAll(
                    vocabularyDays: vocabularyDays,
                    lcDays: lcDays,
                    grammarNotes: grammarNotes,
                    customStudyPages: customStudyPages
                )
            case .vocabularyDay:
                guard let selectedBackupDay else { return }
                archive = AppDataBackupService.archiveVocabularyDay(selectedBackupDay)
            }
            let json = try AppDataBackupService.encode(archive)
            backupDocument = VocaDayBackupDocument(data: Data(json.utf8))
            backupStatusMessage = nil
            isExportingBackup = true
        } catch {
            backupStatusMessage = "백업 파일을 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            guard data.count <= 50 * 1_024 * 1_024,
                  let json = String(data: data, encoding: .utf8) else {
                throw AppDataBackupError.invalidFile
            }

            let archive = try AppDataBackupService.decode(json)
            let preview = AppDataBackupService.preview(
                archive,
                vocabularyDays: vocabularyDays,
                lcDays: lcDays,
                grammarNotes: grammarNotes,
                customStudyPages: customStudyPages
            )
            pendingRestoreArchive = archive
            restoreSummary = preview.summary
            backupStatusMessage = nil
            showsRestoreConfirmation = true
        } catch {
            if !isUserCancellation(error) {
                backupStatusMessage = "백업 파일을 읽지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    private func restorePendingBackup() {
        guard let archive = pendingRestoreArchive else { return }

        do {
            try AppDataBackupService.applyUpsert(
                archive,
                in: modelContext,
                vocabularyDays: vocabularyDays,
                lcDays: lcDays,
                grammarNotes: grammarNotes,
                customStudyPages: customStudyPages
            )
            backupStatusMessage = "백업 데이터를 현재 데이터와 병합했습니다."
        } catch {
            backupStatusMessage = "백업을 복원하지 못했습니다: \(error.localizedDescription)"
        }

        pendingRestoreArchive = nil
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError
    }

    private func ensureSelectedBackupDay() {
        if let selectedBackupDayID,
           vocabularyDays.contains(where: { $0.id == selectedBackupDayID }) {
            return
        }
        selectedBackupDayID = vocabularyDays.first?.id
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
    .modelContainer(for: [VocabularyDay.self, VocaWord.self, LCDictationDay.self, LCDictationNote.self, GrammarNote.self, CustomStudyPage.self], inMemory: true)
}
