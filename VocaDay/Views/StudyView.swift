import SwiftData
import SwiftUI

struct StudyView: View {
    @Query(sort: \GrammarNote.updatedAt, order: .reverse) private var grammarNotes: [GrammarNote]
    @Query(sort: \LCDictationDay.createdAt) private var lcDays: [LCDictationDay]
    @Query(sort: \CustomStudyPage.updatedAt, order: .reverse) private var customPages: [CustomStudyPage]

    @State private var isShowingPageCreator = false

    private var recentGrammarNotes: [GrammarNote] {
        Array(grammarNotes.prefix(3))
    }

    private var lcNoteCount: Int {
        lcDays.reduce(0) { $0 + $1.noteList.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("기본 학습")
                        .font(.headline)
                    Text("VocaDay가 제공하는 기본 학습 공간입니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    NavigationLink {
                        LCDictationView()
                    } label: {
                        studyCard(
                            title: "LC 받아쓰기",
                            subtitle: "문장을 듣고 받아쓰며 틀린 표현을 기록해요.",
                            count: lcNoteCount,
                            countLabel: "받아쓰기 줄",
                            systemImage: "headphones"
                        )
                    }

                    NavigationLink {
                        GrammarNotesView()
                    } label: {
                        studyCard(
                            title: "문법 노트",
                            subtitle: "문법 규칙과 예문을 Markdown으로 정리해요.",
                            count: grammarNotes.count,
                            countLabel: "페이지",
                            systemImage: "text.book.closed"
                        )
                    }
                }
                .buttonStyle(.plain)
                .onboardingSpotlight(.study)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("내 학습 페이지")
                                .font(.headline)
                            Text("마크다운 문서나 직접 구성한 표로 학습 자료를 정리하세요.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            isShowingPageCreator = true
                        } label: {
                            Label("페이지 만들기", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }

                    if customPages.isEmpty {
                        Button {
                            isShowingPageCreator = true
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "plus.square.dashed")
                                    .font(.title)
                                Text("첫 학습 페이지 만들기")
                                    .font(.headline)
                                Text("필기 중심이면 마크다운, 항목별 정리라면 표를 선택하세요.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .calmCard()
                        }
                        .buttonStyle(.plain)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(customPages) { page in
                                NavigationLink {
                                    CustomStudyPageDetailView(page: page)
                                } label: {
                                    customPageCard(page)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)

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
        .navigationTitle("학습")
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button {
                    isShowingPageCreator = true
                } label: {
                    Label("새 학습 페이지", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingPageCreator) {
            CreateStudyPageView()
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 12)]
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    private func customPageCard(_ page: CustomStudyPage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: page.iconName)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(page.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(page.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label(page.kind.title, systemImage: page.kind.systemImage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
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
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12))
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
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        StudyView()
    }
    .modelContainer(for: [LCDictationDay.self, LCDictationNote.self, GrammarNote.self, CustomStudyPage.self], inMemory: true)
}
