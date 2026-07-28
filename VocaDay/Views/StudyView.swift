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
                            subtitle: "받아쓰기와 듣기 노트",
                            count: lcDays.count,
                            countLabel: "노트",
                            systemImage: "headphones"
                        )
                    }

                    NavigationLink {
                        GrammarNotesView()
                    } label: {
                        studyCard(
                            title: "문법 노트",
                            subtitle: "문법, 표, 예문을 위한 Markdown 노트",
                            count: grammarNotes.count,
                            countLabel: "페이지",
                            systemImage: "text.book.closed"
                        )
                    }
                }
                .buttonStyle(.plain)

                if !recentGrammarNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("최근 문법 노트")
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
        .onboardingSpotlight(.study)
        .navigationTitle("학습")
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 12)]
    }

    private func studyCard(
        title: String,
        subtitle: String,
        count: Int,
        countLabel: String,
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
