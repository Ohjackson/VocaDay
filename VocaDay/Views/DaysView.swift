import SwiftData
import SwiftUI

struct DaysView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]

    @Binding var selectedDayID: UUID?

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
            Button {
                let day = DayFactory.createNextDay(existingDays: days, in: modelContext)
                selectedDayID = day.id
            } label: {
                Label("New Day", systemImage: "plus")
            }
        }
    }
}

#Preview {
    NavigationStack {
        DaysView(selectedDayID: .constant(nil))
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
