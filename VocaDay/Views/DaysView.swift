import SwiftData
import SwiftUI

struct DaysView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]

    @Binding var selectedDayID: UUID?
    @State private var isEditingDays = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if days.isEmpty {
                    EmptyStateView(
                        title: "No Day exists yet. Create Day 1.",
                        systemImage: "calendar.badge.plus"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(days) { day in
                            dayRow(for: day)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 840, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("VocaDay")
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Button {
                    isEditingDays.toggle()
                } label: {
                    Image(systemName: isEditingDays ? "checkmark" : "square.and.pencil")
                }
                .accessibilityLabel(isEditingDays ? "Done Editing Days" : "Edit Days")
                .disabled(days.isEmpty)

                Button {
                    let day = DayFactory.createNextDay(existingDays: days, in: modelContext)
                    selectedDayID = day.id
                } label: {
                    Label("New Day", systemImage: "plus")
                }
            }
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

                Button(role: .destructive) {
                    delete(day)
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(day.title)")
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
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
