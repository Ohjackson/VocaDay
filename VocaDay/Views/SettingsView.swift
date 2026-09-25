import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \VocabularyDay.createdAt) private var vocabularyDays: [VocabularyDay]
    @Query(sort: \StudyMemo.updatedAt, order: .reverse) private var studyMemos: [StudyMemo]
    @Query(sort: \StudyPageCategory.createdAt) private var studyPageCategories: [StudyPageCategory]

    @AppStorage("isJSONImportEnabled") private var isJSONImportEnabled = false
    @AppStorage("isAppleIntelligenceWordGenerationEnabled") private var isAppleIntelligenceWordGenerationEnabled = true
    @AppStorage(SpotlightOnboardingCompletion.versionedKey) private var hasCompletedSpotlightOnboarding = false
    @AppStorage("isReviewReminderEnabled") private var isReviewReminderEnabled = false
    @AppStorage("reviewReminderMinutesSinceMidnight") private var reviewReminderMinutesSinceMidnight = 20 * 60
    private let wordGenerationService: any EnglishWordGenerating = AppleFoundationWordGenerationService()
    @State private var showsDeleteConfirmation = false
    @State private var deletionStatusMessage: String?
    @State private var reviewReminderStatusMessage: String?
    #if DEBUG
    @State private var showsStudyMemoResetConfirmation = false
    @State private var studyMemoDebugStatusMessage: String?
    #endif

    private var wordCount: Int {
        vocabularyDays.reduce(0) { $0 + $1.wordList.count }
    }

    private var wordGenerationAvailability: EnglishWordGenerationAvailability {
        wordGenerationService.availability
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text("자동")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("iCloud 동기화", systemImage: "icloud")
                }
            } header: {
                Text("동기화")
            } footer: {
                Text("기기의 Apple 계정과 iCloud 설정을 사용해 개인 CloudKit 저장소로 자동 동기화합니다. 한 기기에서 삭제한 내용도 다른 기기에 반영될 수 있습니다.")
            }

            Section("데이터") {
                NavigationLink(value: AppRoute.settingsBackup) {
                    SettingsNavigationLabel(
                        title: "JSON 파일 백업 및 복원",
                        subtitle: "전체 데이터 또는 선택한 데이를 파일로 보관",
                        systemImage: "externaldrive"
                    )
                }

                LabeledContent("저장된 단어", value: "\(wordCount)개")
                LabeledContent("학습 메모", value: "\(studyMemos.count)개")
                LabeledContent("학습 메모 분류", value: "\(studyPageCategories.count)개")
            }

            Section {
                if wordGenerationAvailability.isDeviceEligible {
                    Toggle(isOn: $isAppleIntelligenceWordGenerationEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Apple Intelligence로 단어 생성")
                            Text("영단어를 입력하면 기기 안에서 뜻과 예문을 자동으로 만들어 줍니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("끄면 단어 추가 화면에서 AI로 생성 버튼이 사라지고 직접 입력만 할 수 있습니다.")
                }

                Toggle(isOn: $isJSONImportEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("외부 AI의 JSON 단어 가져오기")
                        Text("외부 AI에서 만든 단어 JSON을 추가 화면으로 가져옵니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("켜면 단어 추가 화면에 JSON 가져오기 방식이 추가됩니다.")
            } header: {
                Text("단어 추가")
            } footer: {
                Text("지원 기기에서는 Apple Intelligence가 기기 안에서 단어 정보를 생성합니다. 단어 추가 과정에서는 입력한 단어를 외부 AI 서비스로 전송하지 않습니다. 시험 탭에서 Gemini API 키를 직접 입력한 경우에만 시험 문제 준비를 위해 Gemini를 사용합니다.")
            }

            Section {
                Toggle(isOn: $isReviewReminderEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("복습 알림")
                        Text("설정한 시간에 오늘 복습할 단어가 있을 때만 알려드려요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("켜면 알림 권한을 요청하고, 복습할 단어가 있는 날에만 알림을 보냅니다.")
                .onChange(of: isReviewReminderEnabled) { _, isEnabled in
                    handleReviewReminderToggleChange(isEnabled)
                }

                if isReviewReminderEnabled {
                    DatePicker("알림 시간", selection: reviewReminderTime, displayedComponents: .hourAndMinute)
                        .onChange(of: reviewReminderMinutesSinceMidnight) { _, _ in
                            Task { await rescheduleReviewReminder() }
                        }
                }

                if let reviewReminderStatusMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reviewReminderStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("설정 앱에서 알림 허용하기", action: openSystemNotificationSettings)
                            .font(.caption)
                    }
                }
            } header: {
                Text("알림")
            } footer: {
                Text("복습할 단어가 없는 날에는 알림을 보내지 않습니다. 기기의 알림 권한이 꺼져 있으면 이 화면에서 다시 켜도 알림이 오지 않으니 설정 앱에서 허용해주세요.")
            }

            Section("사용 안내") {
                Button {
                    restartOnboarding()
                } label: {
                    SettingsNavigationLabel(
                        title: "스포트라이트 안내 다시 보기",
                        subtitle: "단어 추가와 복습의 핵심 4단계를 다시 확인",
                        systemImage: "sparkles.rectangle.stack"
                    )
                }
                .buttonStyle(.plain)
            }

            Section("정보") {
                NavigationLink(value: AppRoute.settingsPrivacy) {
                    SettingsNavigationLabel(
                        title: "개인정보 및 서비스 안내",
                        subtitle: "로그인, 결제, 광고와 데이터 처리 확인",
                        systemImage: "hand.raised"
                    )
                }
            }

            #if DEBUG
            Section {
                Button {
                    restartOnboarding()
                } label: {
                    Label("전체 스포트라이트 절차 체험", systemImage: "scope")
                }

                Button(role: .destructive) {
                    showsStudyMemoResetConfirmation = true
                } label: {
                    Label("학습 메모 초기화", systemImage: "trash")
                }
                .disabled(studyMemos.isEmpty && studyPageCategories.isEmpty)
                .accessibilityHint("모든 학습 메모와 분류를 삭제합니다. 되돌릴 수 없습니다.")

                Button {
                    recreateStudyMemoDemos()
                } label: {
                    Label("최초 설치 데모 생성", systemImage: "sparkles")
                }
                .accessibilityHint("기본 데모 학습 메모 3개를 다시 만듭니다.")

                Button {
                    importEvenlyDistributedRealData()
                } label: {
                    Label("균등배분 데이터 넣기", systemImage: "square.stack.3d.up")
                }
                .accessibilityHint("앱에 포함된 실제 단어 데이터를 데이별로 균등하게 나누어 현재 데이터와 병합합니다.")

                if let studyMemoDebugStatusMessage {
                    Text(studyMemoDebugStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("디버그")
            } footer: {
                Text("스포트라이트 체험은 실제 데이터를 변경하지 않습니다. 초기화는 학습 메모와 분류만 삭제하며, 데모 생성은 사용자 메모를 유지하고 기본 데모 3개를 다시 만듭니다. 균등배분 데이터 넣기는 번들에 포함된 실제 단어 데이터를 데이별로 고르게 나눠 현재 데이터에 병합합니다.")
            }
            #endif

            Section {
                Button("모든 앱 데이터 삭제", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .disabled(!hasStoredData)
                .accessibilityHint("저장한 데이, 단어, 복습 기록과 학습 메모를 모두 삭제합니다. 되돌릴 수 없습니다.")

                if let deletionStatusMessage {
                    Text(deletionStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("저장한 데이, 단어, 복습 기록과 학습 메모를 모두 삭제하며 되돌릴 수 없습니다.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("설정")
        .confirmationDialog("모든 앱 데이터를 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("모든 데이터 삭제", role: .destructive, action: deleteAllData)
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장한 데이, 단어, 복습 기록과 학습 메모가 모두 삭제되며 되돌릴 수 없습니다.")
        }
        #if DEBUG
        .confirmationDialog(
            "학습 메모를 초기화할까요?",
            isPresented: $showsStudyMemoResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("학습 메모와 분류 삭제", role: .destructive, action: resetStudyMemos)
            Button("취소", role: .cancel) {}
        } message: {
            Text("모든 학습 메모와 직접 만든 분류가 삭제됩니다. 단어 데이와 복습 기록은 유지됩니다.")
        }
        #endif
    }

    private var hasStoredData: Bool {
        !vocabularyDays.isEmpty || !studyMemos.isEmpty || !studyPageCategories.isEmpty
    }

    private func restartOnboarding() {
        hasCompletedSpotlightOnboarding = false
        dismiss()
    }

    private var reviewReminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reviewReminderMinutesSinceMidnight / 60,
                    minute: reviewReminderMinutesSinceMidnight % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reviewReminderMinutesSinceMidnight = (components.hour ?? 20) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func handleReviewReminderToggleChange(_ isEnabled: Bool) {
        guard isEnabled else {
            ReviewReminderService.cancelReminder()
            return
        }

        Task {
            let granted = await ReviewReminderService.requestAuthorization()
            guard granted else {
                reviewReminderStatusMessage = "알림 권한이 꺼져 있어요. 기기 설정 앱에서 VocaDay 알림을 허용해주세요."
                isReviewReminderEnabled = false
                return
            }
            reviewReminderStatusMessage = nil
            await rescheduleReviewReminder()
        }
    }

    private func rescheduleReviewReminder() async {
        guard isReviewReminderEnabled else { return }
        let dueCount = StudyQueue.snapshot(in: modelContext).reminderCount
        await ReviewReminderService.refreshReminder(
            dueWordCount: dueCount,
            hour: reviewReminderMinutesSinceMidnight / 60,
            minute: reviewReminderMinutesSinceMidnight % 60
        )
    }

    private func openSystemNotificationSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
        #endif
    }

    private func deleteAllData() {
        do {
            try AppDataBackupService.deleteAll(
                in: modelContext,
                vocabularyDays: vocabularyDays,
                studyMemos: studyMemos,
                studyPageCategories: studyPageCategories
            )
            deletionStatusMessage = "모든 앱 데이터를 삭제했습니다."
        } catch {
            deletionStatusMessage = "데이터를 삭제하지 못했습니다. 앱을 다시 연 뒤 시도하세요."
        }
    }

    #if DEBUG
    private func resetStudyMemos() {
        do {
            for memo in studyMemos {
                modelContext.delete(memo)
            }
            for category in studyPageCategories {
                modelContext.delete(category)
            }
            try modelContext.save()
            studyMemoDebugStatusMessage = "학습 메모와 분류를 초기화했습니다."
        } catch {
            studyMemoDebugStatusMessage = "학습 메모를 초기화하지 못했습니다. 앱을 다시 연 뒤 시도하세요."
        }
    }

    private func recreateStudyMemoDemos() {
        do {
            try StudyMemoDemoSeeder.recreateDemos(in: modelContext)
            studyMemoDebugStatusMessage = "최초 설치용 학습 메모 데모 3개를 생성했습니다."
        } catch {
            studyMemoDebugStatusMessage = "데모를 생성하지 못했습니다. 앱을 다시 연 뒤 시도하세요."
        }
    }

    private func importEvenlyDistributedRealData() {
        do {
            let archive = try RealDataImporter.loadArchive()
            try AppDataBackupService.applyUpsert(
                archive,
                in: modelContext,
                vocabularyDays: vocabularyDays,
                studyMemos: studyMemos,
                studyPageCategories: studyPageCategories
            )
            studyMemoDebugStatusMessage = "균등배분한 실제 데이터를 현재 데이터와 병합했습니다."
        } catch {
            studyMemoDebugStatusMessage = "균등배분 데이터를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }
    #endif
}

struct JSONBackupView: View {
    @Query(sort: \VocabularyDay.createdAt) private var vocabularyDays: [VocabularyDay]
    @Query(sort: \StudyMemo.updatedAt, order: .reverse) private var studyMemos: [StudyMemo]
    @Query(sort: \StudyPageCategory.createdAt) private var studyPageCategories: [StudyPageCategory]
    @Environment(\.modelContext) private var modelContext

    @AppStorage("lastSuccessfulBackupAt") private var lastSuccessfulBackupAt = 0.0
    @AppStorage("preferredBackupExportScope") private var backupExportScope: BackupExportScope = .allData
    @State private var selectedBackupDayID: UUID?
    @State private var backupStatusMessage: String?
    @State private var backupDocument = VocaDayBackupDocument()
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingRestoreArchive: AppDataArchive?
    @State private var restoreSummary = ""
    @State private var showsRestoreConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker("백업 범위", selection: $backupExportScope) {
                    ForEach(BackupExportScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if backupExportScope == .vocabularyDay {
                    if vocabularyDays.isEmpty {
                        Label("백업할 단어 데이가 없습니다.", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("백업할 데이", selection: $selectedBackupDayID) {
                            ForEach(vocabularyDays) { day in
                                Text("\(day.title) · \(day.wordList.count)단어")
                                    .tag(Optional(day.id))
                            }
                        }
                    }
                } else {
                    LabeledContent("단어 데이", value: "\(vocabularyDays.count)개")
                    LabeledContent("저장된 단어", value: "\(wordCount)개")
                    LabeledContent("학습 메모", value: "\(studyMemos.count)개")
                    LabeledContent("학습 메모 분류", value: "\(studyPageCategories.count)개")
                }
            } header: {
                Text("백업할 데이터")
            } footer: {
                Text(backupExportScope == .allData
                     ? "모든 단어 데이, 단어·복습 기록과 학습 메모를 포함합니다."
                     : "선택한 단어 데이와 그 안의 단어·복습 기록만 포함합니다.")
            }

            Section {
                Button {
                    prepareBackup()
                } label: {
                    Label(backupExportScope == .allData ? "전체 백업 파일 저장" : "선택한 데이 백업", systemImage: "square.and.arrow.up")
                }
                .disabled(!hasExportableBackupData)
                .accessibilityHint("저장 위치를 선택하는 창이 열립니다.")

                Button {
                    isImportingBackup = true
                } label: {
                    Label("JSON 백업에서 복원", systemImage: "square.and.arrow.down")
                }
                .accessibilityHint("백업 파일을 선택하면 현재 데이터와 병합합니다.")

                if lastSuccessfulBackupAt > 0 {
                    LabeledContent("마지막 파일 백업") {
                        Text(Date(timeIntervalSince1970: lastSuccessfulBackupAt), format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }

                if let backupStatusMessage {
                    Text(backupStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("파일")
            } footer: {
                Text("JSON은 사람이 읽을 수 있는 텍스트 파일입니다. 파일 앱에서 나의 iPhone이나 iCloud Drive 등 저장 위치를 직접 선택할 수 있습니다.")
            }

            Section("보안 안내") {
                Label("파일에는 입력한 단어, 복습 기록과 학습 메모가 그대로 포함됩니다.", systemImage: "lock.doc")
                Text("공유 기기나 공개 폴더에는 저장하지 마세요. 복원할 때는 현재 데이터를 지우지 않고 같은 항목을 업데이트하며 없는 항목을 추가합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("JSON 백업 및 복원")
        .confirmationDialog("백업 데이터를 복원할까요?", isPresented: $showsRestoreConfirmation, titleVisibility: .visible) {
            Button("현재 데이터와 병합", action: restorePendingBackup)
            Button("취소", role: .cancel) { pendingRestoreArchive = nil }
        } message: {
            Text("\(restoreSummary)\n\n현재 데이터는 먼저 삭제하지 않습니다.")
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
        .onChange(of: vocabularyDays.map(\.id)) { _, _ in ensureSelectedBackupDay() }
    }

    private var hasStoredData: Bool {
        !vocabularyDays.isEmpty || !studyMemos.isEmpty || !studyPageCategories.isEmpty
    }

    private var wordCount: Int {
        vocabularyDays.reduce(0) { $0 + $1.wordList.count }
    }

    private var selectedBackupDay: VocabularyDay? {
        guard let selectedBackupDayID else { return nil }
        return vocabularyDays.first { $0.id == selectedBackupDayID }
    }

    private var hasExportableBackupData: Bool {
        backupExportScope == .allData ? hasStoredData : selectedBackupDay != nil
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

    private func prepareBackup() {
        do {
            let archive: AppDataArchive
            switch backupExportScope {
            case .allData:
                archive = AppDataBackupService.archiveAll(
                    vocabularyDays: vocabularyDays,
                    studyMemos: studyMemos,
                    studyPageCategories: studyPageCategories
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
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            guard data.count <= 50 * 1_024 * 1_024,
                  let json = String(data: data, encoding: .utf8) else {
                throw AppDataBackupError.invalidFile
            }

            let archive = try AppDataBackupService.decode(json)
            let preview = AppDataBackupService.preview(
                archive,
                vocabularyDays: vocabularyDays,
                studyMemos: studyMemos,
                studyPageCategories: studyPageCategories
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
                studyMemos: studyMemos,
                studyPageCategories: studyPageCategories
            )
            backupStatusMessage = "백업 데이터를 현재 데이터와 병합했습니다."
        } catch {
            backupStatusMessage = "백업을 복원하지 못했습니다: \(error.localizedDescription)"
        }
        pendingRestoreArchive = nil
    }

    private func ensureSelectedBackupDay() {
        if let selectedBackupDayID,
           vocabularyDays.contains(where: { $0.id == selectedBackupDayID }) {
            return
        }
        selectedBackupDayID = vocabularyDays.first?.id
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError
    }
}

struct PrivacyAndServiceView: View {
    var body: some View {
        Form {
            Section("서비스 운영") {
                serviceRow(
                    title: "회원가입·로그인 없음",
                    description: "VocaDay 계정을 만들지 않습니다. iCloud는 기기에 로그인된 Apple 계정을 사용합니다.",
                    systemImage: "person.crop.circle.badge.xmark"
                )
                serviceRow(
                    title: "결제·구독 없음",
                    description: "인앱 결제나 유료 구독 없이 모든 기능을 사용할 수 있습니다.",
                    systemImage: "creditcard"
                )
                serviceRow(
                    title: "광고·사용자 추적 없음",
                    description: "광고를 표시하지 않으며 광고 식별자나 앱 사용 행동을 추적하지 않습니다.",
                    systemImage: "eye.slash"
                )
            }

            Section("데이터 처리") {
                serviceRow(
                    title: "개인 iCloud 동기화",
                    description: "단어, 복습 기록과 학습 메모는 사용자의 개인 CloudKit 저장소를 통해 기기 사이에서 동기화될 수 있습니다.",
                    systemImage: "icloud"
                )
                serviceRow(
                    title: "외부 AI는 사용자가 켤 때만",
                    description: "JSON 기능은 사용자가 직접 복사하고 붙여넣을 때만 동작합니다. 시험 설정에 본인의 Gemini API 키를 입력하면, 시험 문제를 만들기 위해 단어·뜻·예문을 Google Gemini API로 보냅니다. 키는 이 기기의 키체인에만 저장됩니다.",
                    systemImage: "hand.raised"
                )
            }

            Section("문서") {
                Link(destination: privacyPolicyURL) {
                    Label("개인정보 처리방침 열기", systemImage: "safari")
                }
                .accessibilityHint("웹 브라우저에서 개인정보 처리방침을 엽니다")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("개인정보 및 서비스")
    }

    private func serviceRow(title: String, description: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://frequent-silene-a12.notion.site/3bd9fbf6504180a8976af906d35a117f")!
    }
}

private struct SettingsNavigationLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self, StudyMemo.self, StudyPageCategory.self, StudyProgress.self, ReviewLog.self], inMemory: true)
}
