import SwiftUI

/// 리스닝 탭 첫 화면. 맨 위 「직접 넣은 글 듣기」, 그 아래 앱에 들어 있는 책 목록.
struct ListeningView: View {
    @Environment(\.readingStore) private var store
    @Environment(\.appNavigate) private var navigate
    private let books = BookLibrary.bundled
    private let importedStore = ImportedBookStore.shared

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRoute.listeningFreeText) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("직접 넣은 글 듣기")
                            Text("영어 글을 붙여 넣고 한 문장씩 들어요")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "text.bubble")
                    }
                }
                NavigationLink(value: AppRoute.pdfImport) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PDF 가져오기")
                            Text("가진 책의 PDF나 스캔본을 책으로 만들어요")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.text.viewfinder")
                    }
                }
            }

            Section {
                if books.isEmpty {
                    Text("앱에 들어 있는 책이 없어요.")
                        .foregroundStyle(.secondary)
                }
                ForEach(books) { book in
                    NavigationLink(value: AppRoute.book(id: book.id)) {
                        BookListRow(book: book, lastPosition: store.lastPosition(bookID: book.id))
                    }
                    .contextMenu {
                        Button("적합도 보기", systemImage: "chart.bar.doc.horizontal") {
                            navigate(.bookFit(bookID: book.id))
                        }
                    }
                }
            } header: {
                Text("책")
            } footer: {
                #if os(macOS)
                Text("단어를 누르면 뜻을, 문장을 우클릭하면 번역을 볼 수 있어요.")
                #else
                Text("단어를 누르면 뜻을, 문장을 길게 누르면 번역을 볼 수 있어요.")
                #endif
            }

            if !importedStore.books.isEmpty {
                Section("가져온 책") {
                    ForEach(importedStore.books) { summary in
                        NavigationLink(value: AppRoute.book(id: summary.id)) {
                            ImportedBookRow(summary: summary)
                        }
                        .contextMenu {
                            Button("적합도 보기", systemImage: "chart.bar.doc.horizontal") {
                                navigate(.bookFit(bookID: summary.id))
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .navigationTitle(AppSection.listening.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: AppRoute.listeningSettings) {
                    Label("사전·음성 설정", systemImage: "gearshape")
                }
                .help("사전·음성 모델 받기와 음성 시험")
            }
        }
        .task {
            importedStore.refresh()
            BookTranslationService.shared.resumePending()
        }
    }
}

private struct BookListRow: View {
    let book: BookDocument
    let lastPosition: ReadingPosition?

    private var navigator: ReadingNavigator { ReadingNavigator(book: book) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCover(book: book)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(.headline, design: .serif))
                if let subtitle = book.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                BookFitReportReader(book: book) { report in
                    if let report { BookFitBadge(report: report, style: .compact) }
                }
                if let lastPosition {
                    HStack(spacing: 8) {
                        ProgressView(value: navigator.progress(of: lastPosition))
                            .frame(maxWidth: 120)
                        Text("\(navigator.ordinal(of: lastPosition)) / \(navigator.count) 문장")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var metaText: String {
        var parts: [String] = []
        if let level = book.level { parts.append(level) }
        parts.append("\(book.chapters.count)장")
        parts.append("\(navigator.count)문장")
        return parts.joined(separator: " · ")
    }
}

/// 표지 대신 쓰는 작은 색 블록. 책 id로 색을 정해 늘 같은 색이 나온다. 책 화면처럼 평평한 색 + 1pt 테두리.
private struct BookCover: View {
    let book: BookDocument

    /// (표지, 테두리, 글자). 책 화면 테마와 어울리는 낡은 천 색.
    private static let palette: [(UInt32, UInt32, UInt32)] = [
        (0x8A5A1F, 0x6E4718, 0xEEE2C4),
        (0x4F6B1F, 0x3F5518, 0xE8EBD7),
        (0x2F5D8A, 0x254A6E, 0xFBFAF6),
        (0x7A4B3A, 0x613B2E, 0xF6EFDF),
    ]

    var body: some View {
        let seed = book.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let colors = Self.palette[seed % Self.palette.count]
        Rectangle()
            .fill(Color(readerHex: colors.0))
            .frame(width: 46, height: 64)
            .overlay {
                Rectangle().strokeBorder(Color(readerHex: colors.1), lineWidth: 1)
            }
            .overlay {
                Text(String(book.title.prefix(1)))
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(readerHex: colors.2))
            }
            .accessibilityHidden(true)
    }
}

/// PDF 로 가져온 책 한 줄. 번역이 다 안 됐으면 진행률을 보인다.
private struct ImportedBookRow: View {
    let summary: ImportedBookSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.title)
                .font(.system(.headline, design: .serif))
            if let author = summary.author {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(metaText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var metaText: String {
        var parts = ["\(summary.chapterCount)장", "\(summary.sentenceCount)문장"]
        if !summary.isFullyTranslated {
            parts.append("번역 \(Int(summary.translationFraction * 100))%")
        }
        return parts.joined(separator: " · ")
    }
}
