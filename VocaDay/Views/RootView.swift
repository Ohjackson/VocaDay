import SwiftData
import SwiftUI

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
                    AddWordsView(selectedDayID: $selectedDayID)
                }
                .tabItem { Label(AppSection.add.title, systemImage: AppSection.add.systemImage) }
                .tag(AppSection.add)

                NavigationStack {
                    ReviewView()
                }
                .tabItem { Label(AppSection.review.title, systemImage: AppSection.review.systemImage) }
                .tag(AppSection.review)

                NavigationStack {
                    LCDictationView()
                }
                .tabItem { Label(AppSection.lcDictation.title, systemImage: AppSection.lcDictation.systemImage) }
                .tag(AppSection.lcDictation)
            }
            #endif
        }
        .task {
            ensureInitialDay()
        }
        .onChange(of: days.map(\.id)) { _, _ in
            ensureSelectedDay()
        }
    }

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .days:
            DaysView(selectedDayID: $selectedDayID)
        case .add:
            AddWordsView(selectedDayID: $selectedDayID)
        case .review:
            ReviewView()
        case .lcDictation:
            LCDictationView()
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
}

#Preview {
    RootView()
        .modelContainer(for: [VocabularyDay.self, VocaWord.self, LCDictationDay.self, LCDictationNote.self], inMemory: true)
}
