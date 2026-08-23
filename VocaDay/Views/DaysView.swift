import SwiftData
import SwiftUI

struct DaysView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]

    @Binding var selectedDayID: UUID?
    @State private var isEditingDays = false
    @State private var isShowingDayTitleAlert = false
    @State private var dayTitle = ""
    @State private var editingDay: VocabularyDay?
    @State private var searchText = ""

    private var filteredDays: [VocabularyDay] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return days }

        return days.filter { day in
            day.title.localizedCaseInsensitiveContains(query) ||
            day.wordList.contains { word in
                word.english.localizedCaseInsensitiveContains(query) ||
                word.meaningKo.localizedCaseInsensitiveContains(query) ||
                word.note.localizedCaseInsensitiveContains(query) ||
                word.toeicTag.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if days.isEmpty {
                    EmptyStateView(
                        title: "아직 데이가 없습니다. 첫 데이를 만들어 보세요.",
                        systemImage: "calendar.badge.plus"
                    )
                } else if filteredDays.isEmpty {
                    EmptyStateView(
                        title: "일치하는 데이가 없습니다.",
                        systemImage: "magnifyingglass"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredDays) { day in
                            dayRow(for: day)
                        }
                    }
                    .onboardingSpotlight(.days)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 840, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("VocaDay")
        .searchable(text: $searchText, prompt: "데이 검색")
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                #if os(iOS)
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("설정")
                #endif

                Button {
                    isEditingDays.toggle()
                } label: {
                    Image(systemName: isEditingDays ? "checkmark" : "square.and.pencil")
                }
                .accessibilityLabel(isEditingDays ? "데이 편집 완료" : "데이 편집")
                .disabled(days.isEmpty)

                Button {
                    editingDay = nil
                    dayTitle = DayFactory.nextDayTitle(existingDays: days)
                    isShowingDayTitleAlert = true
                } label: {
                    Label("새 데이", systemImage: "plus")
                }
            }
        }
        .alert(editingDay == nil ? "새 데이" : "데이 이름 변경", isPresented: $isShowingDayTitleAlert) {
            TextField("제목", text: $dayTitle)

            Button("취소", role: .cancel) {
                resetDayTitleEditor()
            }

            Button(editingDay == nil ? "만들기" : "저장") {
                saveDayTitle()
            }
            .disabled(dayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("데이 제목을 입력하세요.")
        }
    }

    @ViewBuilder
    private func dayRow(for day: VocabularyDay) -> some View {
        if isEditingDays {
            HStack(spacing: 10) {
                DayCardView(
                    day: day,
                    isSelected: selectedDayID == day.id
                )

                Button {
                    editingDay = day
                    dayTitle = day.title
                    isShowingDayTitleAlert = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(day.title) 이름 변경")

                Button(role: .destructive) {
                    delete(day)
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(day.title) 삭제")
            }
        } else {
            NavigationLink {
                DayWordsDetailView(initialDay: day)
            } label: {
                DayCardView(
                    day: day,
                    isSelected: selectedDayID == day.id
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                selectedDayID = day.id
            })
        }
    }

    private func saveDayTitle() {
        let title = dayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        if let editingDay {
            editingDay.title = title
            selectedDayID = editingDay.id
        } else {
            let day = DayFactory.createDay(title: title, in: modelContext)
            selectedDayID = day.id
        }

        try? modelContext.save()
        resetDayTitleEditor()
    }

    private func resetDayTitleEditor() {
        editingDay = nil
        dayTitle = ""
    }

    private func delete(_ day: VocabularyDay) {
        if selectedDayID == day.id {
            selectedDayID = nil
        }

        modelContext.delete(day)
        try? modelContext.save()

        if days.count <= 1 {
            isEditingDays = false
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

#Preview {
    NavigationStack {
        DaysView(selectedDayID: .constant(nil))
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self, LCDictationDay.self, LCDictationNote.self, GrammarNote.self], inMemory: true)
}
