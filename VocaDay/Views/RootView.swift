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

    var title: LocalizedStringKey {
        switch self {
        case .days:
            return "Days"
        case .add:
            return "Add"
        case .review:
            return "Review"
        case .lcDictation:
            return "Study"
        case .settings:
            return "Settings"
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

    var title: LocalizedStringKey {
        switch self {
        case .days: "Build your vocabulary by Day"
        case .addMode: "Choose how you want to add words"
        case .addInput: "Add a word in seconds"
        case .jsonInput: "Import multiple words with JSON"
        case .addActions: "Use clear actions to manage your list"
        case .review: "Review words when you are ready"
        case .study: "Keep grammar and listening notes together"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .days: "Create a Day for each study session, then open it to see every saved word."
        case .addMode: "Use Manual Input for one word at a time, or switch to JSON to bring in a prepared word list."
        case .addInput: "Type an English word and VocaDay adds it to your temporary list with a Korean translation."
        case .jsonInput: "Paste a JSON array, import it into the temporary list, then review and save it to your Day."
        case .addActions: "Paste or copy JSON, remove a selected word, and save the completed list to your Day."
        case .review: "Hide meanings, mark difficult words as Again, and finish a review to update your progress."
        case .study: "Use Study for LC dictation and Markdown grammar notes alongside your vocabulary."
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
            Button("Quick Add Word") {
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

                Text("Quick Add Word")
                    .font(.headline)

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close")
            }

            TextField("English word or phrase", text: $text)
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
                Label("Add to Latest Day", systemImage: "tray.and.arrow.down")
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
