import SwiftData
import SwiftUI

struct StudyView: View {
    @Query(sort: \GrammarNote.updatedAt, order: .reverse) private var grammarNotes: [GrammarNote]
    @Query(sort: \LCDictationDay.createdAt) private var lcDays: [LCDictationDay]

    private var recentGrammarNotes: [GrammarNote] {
        Array(grammarNotes.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: columns, spacing: 12) {
                    NavigationLink {
                        LCDictationView()
                    } label: {
                        studyCard(
                            title: "LC",
                            subtitle: "Dictation lines and listening notes",
                            count: lcDays.count,
                            countLabel: "Notes",
                            systemImage: "headphones"
                        )
                    }

                    NavigationLink {
                        GrammarNotesView()
                    } label: {
                        studyCard(
                            title: "Grammar Notes",
                            subtitle: "Markdown notes for grammar, tables, and examples",
                            count: grammarNotes.count,
                            countLabel: "Pages",
                            systemImage: "text.book.closed"
                        )
                    }
                }
                .buttonStyle(.plain)

                if !recentGrammarNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Grammar Notes")
                            .font(.headline)

                        LazyVStack(spacing: 10) {
                            ForEach(recentGrammarNotes) { note in
                                NavigationLink {
                                    GrammarNoteDetailView(note: note)
                                } label: {
                                    GrammarNoteRowView(note: note)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("Study")
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 12)]
    }

    private func studyCard(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        count: Int,
        countLabel: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Text("\(count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Text(countLabel)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .calmCard()
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        StudyView()
    }
    .modelContainer(for: [LCDictationDay.self, LCDictationNote.self, GrammarNote.self], inMemory: true)
}
