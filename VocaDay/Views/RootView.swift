import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

enum AppSection: CaseIterable, Identifiable, Hashable {
    case days
    case add
    case review
    case studyMemos

    var id: Self { self }

    var title: String {
        switch self {
        case .days:
            return "데이"
        case .add:
            return "추가"
        case .review:
            return "복습"
        case .studyMemos:
            return "학습 메모"
        }
    }

    var systemImage: String {
        switch self {
        case .days:
            return "calendar"
        case .add:
            return "plus.circle"
        case .review:
            return "rectangle.stack"
        case .studyMemos:
            return "note.text"
        }
    }
}

struct RootView: View {
    @AppStorage(SpotlightOnboardingCompletion.versionedKey) private var hasCompletedOnboarding = false
    @StateObject private var onboardingController = SpotlightFlowController()
    @State private var initialProductionSection: AppSection = .days

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ProductionRootView(initialSection: initialProductionSection)
            } else {
                VocaDayOnboardingScene(controller: onboardingController) {
                    initialProductionSection = .add
                    hasCompletedOnboarding = true
                }
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if !completed {
                onboardingController.prepareForPresentation()
            }
        }
    }
}

private struct ProductionRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]

    @AppStorage("isReviewReminderEnabled") private var isReviewReminderEnabled = false
    @AppStorage("reviewReminderMinutesSinceMidnight") private var reviewReminderMinutesSinceMidnight = 20 * 60

    @State private var selectedSection: AppSection
    @State private var selectedDayID: UUID?
    @State private var isShowingQuickAdd = false
    @State private var quickAddText = ""
    @State private var quickAddWord: String?
    @State private var addEntryMode: AddEntryMode = .manual

    init(initialSection: AppSection = .days) {
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        Group {
            #if os(macOS)
            MacAppNavigationShell(selectedSection: $selectedSection) { section in
                NavigationStack {
                    destination(for: section)
                }
                .id(section)
            }
            #else
            TabView(selection: $selectedSection) {
                NavigationStack {
                    DaysView(selectedDayID: $selectedDayID)
                }
                .tabItem { Label(AppSection.days.title, systemImage: AppSection.days.systemImage) }
                .tag(AppSection.days)

                NavigationStack {
                    AddWordsView(selectedDayID: $selectedDayID, quickAddWord: $quickAddWord, entryMode: $addEntryMode)
                }
                .tabItem { Label(AppSection.add.title, systemImage: AppSection.add.systemImage) }
                .tag(AppSection.add)

                NavigationStack {
                    ReviewView()
                }
                .tabItem { Label(AppSection.review.title, systemImage: AppSection.review.systemImage) }
                .tag(AppSection.review)

                NavigationStack {
                    StudyMemoFeatureView()
                }
                .tabItem { Label(AppSection.studyMemos.title, systemImage: AppSection.studyMemos.systemImage) }
                .tag(AppSection.studyMemos)

            }
            #endif
        }
        .overlay {
            if isShowingQuickAdd {
                quickAddOverlay
            }
        }
        .background {
            Button("빠른 단어 추가") {
                openQuickAdd()
            }
            .keyboardShortcut("j", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .task {
            ensureInitialDay()
            rescheduleReviewReminderIfNeeded()
        }
        .onChange(of: days.map(\.id)) { _, _ in
            ensureSelectedDay()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                rescheduleReviewReminderIfNeeded()
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: quickAddRequestedNotification)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openQuickAdd()
        }
        #endif
    }

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .days:
            DaysView(selectedDayID: $selectedDayID)
        case .add:
            AddWordsView(selectedDayID: $selectedDayID, quickAddWord: $quickAddWord, entryMode: $addEntryMode)
        case .review:
            ReviewView()
        case .studyMemos:
            StudyMemoFeatureView()
        }
    }

    private func ensureInitialDay() {
        DemoDataSeeder.seedIfNeeded(existingDays: days, in: modelContext)
        ensureSelectedDay()
    }

    private func rescheduleReviewReminderIfNeeded() {
        guard isReviewReminderEnabled else { return }
        let dueCount = ReviewScheduler.dueWordCount(in: days)
        let hour = reviewReminderMinutesSinceMidnight / 60
        let minute = reviewReminderMinutesSinceMidnight % 60
        Task {
            await ReviewReminderService.refreshReminder(dueWordCount: dueCount, hour: hour, minute: minute)
        }
    }

    private func ensureSelectedDay() {
        guard !days.isEmpty else {
            selectedDayID = nil
            return
        }

        if let selectedDayID, days.contains(where: { $0.id == selectedDayID }) {
            return
        }

        selectedDayID = days.last?.id
    }

    private var quickAddOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    closeQuickAdd()
                }

            QuickAddWordPanel(
                text: $quickAddText,
                onSubmit: submitQuickAdd,
                onCancel: closeQuickAdd
            )
            .padding(.horizontal, 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func openQuickAdd() {
        quickAddText = ""
        withAnimation(.easeInOut(duration: 0.16)) {
            isShowingQuickAdd = true
        }
    }

    private func closeQuickAdd() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isShowingQuickAdd = false
        }
    }

    private func submitQuickAdd() {
        let english = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !english.isEmpty else { return }

        let targetDay = mostRecentDay() ?? DayFactory.createNextDay(existingDays: days, in: modelContext)
        selectedDayID = targetDay.id
        selectedSection = .add
        addEntryMode = .manual
        quickAddWord = english
        closeQuickAdd()
    }

    private func mostRecentDay() -> VocabularyDay? {
        days.sorted { $0.createdAt < $1.createdAt }.last
    }

}

private struct QuickAddWordPanel: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                Text("빠른 단어 추가")
                    .font(.headline)

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("닫기")
            }

            TextField("영단어 또는 구문", text: $text)
                .textFieldStyle(.roundedBorder)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()
                .focused($isFocused)
                .onSubmit(onSubmit)

            Button {
                onSubmit()
            } label: {
                Label("최근 데이에 추가", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .frame(maxWidth: 460)
        .calmCard()
        .onAppear {
            isFocused = true
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [VocabularyDay.self, VocaWord.self, StudyMemo.self, StudyPageCategory.self], inMemory: true)
}
