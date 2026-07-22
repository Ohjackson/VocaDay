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

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]

    @State private var selectedSection: AppSection = .days
    @State private var selectedDayID: UUID?
    @State private var isShowingQuickAdd = false
    @State private var quickAddText = ""
    @State private var quickAddWord: String?

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
                    AddWordsView(selectedDayID: $selectedDayID, quickAddWord: $quickAddWord)
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
            AddWordsView(selectedDayID: $selectedDayID, quickAddWord: $quickAddWord)
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
