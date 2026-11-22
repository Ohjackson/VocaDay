import SwiftUI

/// 목차·북마크. iPhone은 시트, Mac은 오른쪽 패널에 들어간다.
struct ReaderContentsPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case contents
        case bookmarks
        var id: Self { self }
        var title: String { self == .contents ? "목차" : "북마크" }
    }

    let session: ReaderSession
    @Binding var tab: Tab
    /// 항목을 고른 뒤 (iPhone 시트 닫기 등).
    var onSelect: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Picker("보기", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            switch tab {
            case .contents:
                contents
            case .bookmarks:
                bookmarks
            }
        }
    }

    private var contents: some View {
        List {
            ForEach(session.navigator.chapterStarts, id: \.self) { start in
                let chapter = session.book.chapters[start.chapter]
                let isCurrent = session.position.chapter == start.chapter
                Button {
                    session.jump(to: start)
                    onSelect()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(start.chapter + 1)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.title)
                                .font(.system(.body, design: .serif))
                                .fontWeight(isCurrent ? .semibold : .regular)
                            Text("\(chapter.paragraphs.reduce(0) { $0 + $1.sentences.count })문장")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isCurrent {
                            Image(systemName: "book.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityLabel("읽는 중")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var bookmarks: some View {
        let marks = session.bookmarks
        if marks.isEmpty {
            ContentUnavailableView {
                Label("북마크가 없어요", systemImage: "bookmark")
            } description: {
                #if os(macOS)
                Text("문장을 우클릭하거나 위의 북마크 버튼을 눌러 추가해요.")
                #else
                Text("문장을 길게 누르거나 위의 북마크 버튼을 눌러 추가해요.")
                #endif
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(marks) { mark in
                    Button {
                        session.jump(to: mark.position)
                        onSelect()
                    } label: {
                        ReaderBookmarkRow(book: session.book, bookmark: mark)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("북마크 삭제", systemImage: "trash", role: .destructive) {
                            session.removeBookmark(mark)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { marks[$0] }.forEach(session.removeBookmark)
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct ReaderBookmarkRow: View {
    let book: BookDocument
    let bookmark: ReaderBookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(book.chapters.indices.contains(bookmark.position.chapter) ? book.chapters[bookmark.position.chapter].title : "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(bookmark.createdAt, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(book.sentence(at: bookmark.position)?.text ?? "")
                .font(.system(.subheadline, design: .serif))
                .lineLimit(2)
            if !bookmark.note.isEmpty {
                Text(bookmark.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
