import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

enum AppSection: CaseIterable, Identifiable, Hashable {
    case days
    case add
    case review
    case lcDictation
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .days:
            return "데이"
        case .add:
            return "추가"
        case .review:
            return "복습"
        case .lcDictation:
            return "학습"
        case .settings:
            return "설정"
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
        case .lcDictation:
            return "headphones"
        case .settings:
            return "gearshape"
        }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case days
    case addMode
    case addInput
    case jsonInput
    case addActions
    case review
    case study

    var target: OnboardingSpotlightTarget {
        switch self {
        case .days: .days
        case .addMode: .addMode
        case .addInput: .addInput
        case .jsonInput: .jsonInput
        case .addActions: .addActions
        case .review: .review
        case .study: .study
        }
    }

    var title: String {
        switch self {
        case .days: "데이별로 단어를 모아 보세요"
        case .addMode: "단어를 추가할 방식을 고르세요"
        case .addInput: "단어를 빠르게 추가하세요"
        case .jsonInput: "JSON으로 여러 단어를 가져오세요"
        case .addActions: "목록을 관리하고 저장하세요"
        case .review: "준비되었을 때 단어를 복습하세요"
        case .study: "문법과 듣기 노트를 함께 관리하세요"
        }
    }

    var message: String {
        switch self {
        case .days: "학습할 때마다 데이를 만들고, 열어서 저장한 단어를 확인하세요."
        case .addMode: "한 단어씩 직접 입력하거나, 준비한 단어 목록을 JSON으로 가져올 수 있어요."
        case .addInput: "영단어를 입력하면 한국어 뜻과 함께 임시 목록에 추가됩니다."
        case .jsonInput: "JSON 배열을 붙여넣어 임시 목록으로 가져온 뒤, 확인하고 데이에 저장하세요."
        case .addActions: "JSON을 붙여넣거나 복사하고, 선택한 단어를 삭제하거나 데이에 저장할 수 있어요."
        case .review: "뜻을 가리고 어려운 단어는 다시로 표시한 뒤 복습을 완료하세요."
        case .study: "학습 탭에서 받아쓰기와 Markdown 문법 노트를 함께 관리하세요."
        }
    }

    var section: AppSection {
        switch self {
        case .days: .days
        case .addMode, .addInput, .jsonInput, .addActions: .add
        case .review: .review
        case .study: .lcDictation
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]

    @State private var selectedSection: AppSection = .days
    @State private var selectedDayID: UUID?
    @State private var isShowingQuickAdd = false
    @State private var quickAddText = ""
    @State private var quickAddWord: String?
    @State private var addEntryMode: AddEntryMode = .manual
    @AppStorage("hasCompletedSpotlightOnboarding") private var hasCompletedSpotlightOnboarding = false
    @State private var onboardingStep: OnboardingStep?

    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                List(AppSection.allCases, selection: $selectedSection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .navigationTitle("VocaDay")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } detail: {
                NavigationStack {
                    destination(for: selectedSection)
                }
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
                    StudyView()
                }
                .tabItem { Label(AppSection.lcDictation.title, systemImage: AppSection.lcDictation.systemImage) }
                .tag(AppSection.lcDictation)
            }
            #endif
        }
        .overlay {
            if isShowingQuickAdd {
                quickAddOverlay
            }
        }
        #if os(iOS)
        .overlayPreferenceValue(OnboardingSpotlightPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let onboardingStep {
                    SpotlightOnboardingOverlay(
                        title: onboardingStep.title,
                        message: onboardingStep.message,
                        step: onboardingStep.rawValue + 1,
                        totalSteps: OnboardingStep.allCases.count,
                        spotlightRect: anchors[onboardingStep.target].map { proxy[$0] },
                        canGoBack: onboardingStep != .days,
                        onBack: showPreviousOnboardingStep,
                        onNext: showNextOnboardingStep,
                        onSkip: finishOnboarding
                    )
                }
            }
        }
        #endif
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
            await presentOnboardingIfNeeded()
        }
        .onChange(of: days.map(\.id)) { _, _ in
            ensureSelectedDay()
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
        case .lcDictation:
            StudyView()
        case .settings:
            SettingsView()
        }
    }

    private func ensureInitialDay() {
        DemoDataSeeder.seedIfNeeded(existingDays: days, in: modelContext)
        ensureSelectedDay()
    }

    private func ensureSelectedDay() {
        guard !days.isEmpty else {
            selectedDayID = nil
            return
        }

        if let selectedDayID, days.contains(where: { $0.id == selectedDayID }) {
            return
        }

        selectedDayID = days.first?.id
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

    @MainActor
    private func presentOnboardingIfNeeded() async {
        #if os(iOS)
        guard !hasCompletedSpotlightOnboarding else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled, !hasCompletedSpotlightOnboarding else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            onboardingStep = .days
        }
        #endif
    }

    private func showPreviousOnboardingStep() {
        guard let onboardingStep,
              let previous = OnboardingStep(rawValue: onboardingStep.rawValue - 1) else { return }
        presentOnboardingStep(previous)
        withAnimation(.easeInOut(duration: 0.2)) {
            self.onboardingStep = previous
        }
    }

    private func showNextOnboardingStep() {
        guard let onboardingStep else { return }
        guard let next = OnboardingStep(rawValue: onboardingStep.rawValue + 1) else {
            finishOnboarding()
            return
        }
        presentOnboardingStep(next)
        withAnimation(.easeInOut(duration: 0.2)) {
            self.onboardingStep = next
        }
    }

    private func presentOnboardingStep(_ step: OnboardingStep) {
        selectedSection = step.section
        switch step {
        case .jsonInput:
            addEntryMode = .json
        case .addMode, .addInput:
            addEntryMode = .manual
        default:
            break
        }
    }

    private func finishOnboarding() {
        hasCompletedSpotlightOnboarding = true
        withAnimation(.easeInOut(duration: 0.2)) {
            onboardingStep = nil
        }
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
        .modelContainer(for: [VocabularyDay.self, VocaWord.self, LCDictationDay.self, LCDictationNote.self, GrammarNote.self], inMemory: true)
}
