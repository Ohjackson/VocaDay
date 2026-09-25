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
    @State private var dayPendingDeletion: VocabularyDay?
    @State private var searchText = ""
    @State private var errorAlert: VocaAlert?

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
        AppCollectionPage(
            maxContentWidth: 840,
            horizontalPadding: 20,
            verticalPadding: 24
        ) {
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
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle("VocaDay")
        .searchable(text: $searchText, prompt: "데이 검색")
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .componentSpotlight(.settingsButton)
                .accessibilityLabel("설정")

                Button {
                    isEditingDays.toggle()
                } label: {
                    Image(systemName: isEditingDays ? "checkmark" : "square.and.pencil")
                }
                .componentSpotlight(.editDaysButton)
                .accessibilityLabel(isEditingDays ? "데이 편집 완료" : "데이 편집")
                .disabled(days.isEmpty)

                Button {
                    editingDay = nil
                    dayTitle = DayFactory.nextDayTitle(existingDays: days)
                    isShowingDayTitleAlert = true
                } label: {
                    AppToolbarActionLabel(title: "새 데이", systemImage: "plus")
                }
                .componentSpotlight(.createDayButton)
                .accessibilityHint("이름을 입력하는 창이 열립니다.")
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
        .confirmationDialog(
            "\(dayPendingDeletion?.title ?? "이 데이")을 삭제할까요?",
            isPresented: Binding(
                get: { dayPendingDeletion != nil },
                set: { if !$0 { dayPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("데이와 단어 삭제", role: .destructive) {
                deletePendingDay()
            }
            Button("취소", role: .cancel) {
                dayPendingDeletion = nil
            }
        } message: {
            Text("포함된 단어 \(dayPendingDeletion?.wordList.count ?? 0)개와 복습 기록이 함께 삭제되며 되돌릴 수 없습니다.")
        }
        .alert(item: $errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
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
                .componentSpotlight(.dayCollection)

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
                    dayPendingDeletion = day
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(day.title) 삭제")
            }
        } else {
            NavigationLink(value: AppRoute.dayWords(dayID: day.id)) {
                DayCardView(
                    day: day,
                    isSelected: selectedDayID == day.id
                )
                .componentSpotlight(.dayCollection)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(day.title), 단어 \(day.wordList.count)개")
            .accessibilityHint("두 번 탭하여 단어 목록을 엽니다.")
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

        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
            return
        }
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
        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
            return
        }

        if days.count <= 1 {
            isEditingDays = false
        }
    }

    private func deletePendingDay() {
        guard let dayPendingDeletion else { return }
        delete(dayPendingDeletion)
        self.dayPendingDeletion = nil
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
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
