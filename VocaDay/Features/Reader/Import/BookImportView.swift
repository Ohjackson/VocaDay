import SwiftUI
import Translation
import UniformTypeIdentifiers

/// 책 가져오기(PDF·TXT) 화면 조각. 파일 고르기, 진행률, 결과(장·문장 수, 번역 상태), 가져온 책 목록.
/// 화면 이동은 하지 않는다. 책을 열 때는 `onOpen(bookID)`를 부르므로 붙이는 쪽이 `AppRoute`로 push 한다.
struct BookImportView: View {
    var onOpen: ((String) -> Void)?

    @State private var importer: BookImporter
    @State private var store: ImportedBookStore
    @State private var translator: BookTranslationService
    @State private var isPickingFile = false
    @State private var packConfiguration: TranslationSession.Configuration?
    @State private var pendingDelete: ImportedBookSummary?

    init(
        store: ImportedBookStore? = nil,
        translator: BookTranslationService? = nil,
        onOpen: ((String) -> Void)? = nil
    ) {
        let store = store ?? .shared
        let translator = translator ?? .shared
        _store = State(initialValue: store)
        _translator = State(initialValue: translator)
        _importer = State(initialValue: BookImporter(store: store, translator: translator))
        self.onOpen = onOpen
    }

    var body: some View {
        Form {
            fileSection
            statusSection
            importedBooksSection
        }
        .formStyle(.grouped)
        .navigationTitle("책 가져오기")
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: BookImporter.allowedContentTypes) { result in
            if case .success(let url) = result {
                Task { await importer.importFile(at: url) }
            }
        }
        .translationTask(packConfiguration) { session in
            // 언어 팩이 없으면 시스템이 받기 안내를 띄운다.
            do {
                try await session.prepareTranslation()
            } catch {}
            await afterPackPrepared()
        }
        .confirmationDialog(
            "가져온 책을 지울까요?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { summary in
            Button("「\(summary.title)」 지우기", role: .destructive) {
                try? store.delete(id: summary.id)
                if case .finished(let finished, _) = importer.phase, finished.id == summary.id { importer.reset() }
            }
        } message: { _ in
            Text("북마크와 읽은 위치는 남아 있어서, 같은 파일을 다시 가져오면 이어서 읽을 수 있어요.")
        }
        .task {
            translator.resumePending()
        }
    }

    // MARK: Sections

    private var fileSection: some View {
        Section {
            Button {
                isPickingFile = true
            } label: {
                Label("파일 고르기 (PDF·TXT)", systemImage: "doc.badge.plus")
            }
            .disabled(importer.isWorking)
        } header: {
            Text("파일에서")
        } footer: {
            Text("PDF: 글자가 있으면 바로, 스캔본은 기기 안에서 글자를 읽어(OCR) 가져와요. 쪽 번호와 반복되는 머리말은 빼요.\nTXT: 빈 줄로 문단을, \"Chapter 1\" 같은 줄로 장을 나눠요.")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch importer.phase {
        case .idle:
            EmptyView()
        case .working(let progress):
            Section("가져오는 중") {
                ProgressView(value: progress.fraction) {
                    Text(progress.message)
                }
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        case .finished(let finished, let alreadyImported):
            let summary = store.summary(id: finished.id) ?? finished
            Section(alreadyImported ? "이미 가져온 책이에요" : "가져왔어요") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title).font(.headline)
                    if let author = summary.author {
                        Text(author).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("\(summary.chapterCount)개 장 · \(summary.sentenceCount)문장")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                translationRow(summary)
                if let onOpen {
                    Button {
                        onOpen(summary.id)
                    } label: {
                        Label("읽기", systemImage: "book")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var importedBooksSection: some View {
        if !store.books.isEmpty {
            Section("가져온 책") {
                ForEach(store.books) { summary in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.title)
                            Text(rowDetail(summary))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let onOpen {
                            Button("읽기") { onOpen(summary.id) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .contextMenu {
                        Button("지우기", systemImage: "trash", role: .destructive) { pendingDelete = summary }
                    }
                    .swipeActions {
                        Button("지우기", systemImage: "trash", role: .destructive) { pendingDelete = summary }
                    }
                }
            }
        }
    }

    // MARK: Translation

    @ViewBuilder
    private func translationRow(_ summary: ImportedBookSummary) -> some View {
        if summary.isFullyTranslated {
            Label("번역 완료", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        } else {
            switch translator.packStatus[summary.language] ?? .unknown {
            case .needsDownload:
                VStack(alignment: .leading, spacing: 6) {
                    Text("번역 언어 팩이 없어요. 받으면 기기 안에서 문장마다 한국어 번역을 채워요. 번역 없이도 바로 읽을 수 있어요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        requestPack(language: summary.language)
                    } label: {
                        Label("번역 언어 팩 받기", systemImage: "arrow.down.circle")
                    }
                }
            case .unsupported:
                Label("이 언어는 기기 안 번역을 지원하지 않아요. 번역 없이 읽을 수 있어요.", systemImage: "character.bubble")
                    .foregroundStyle(.secondary)
            case .installed, .unknown:
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: summary.translationFraction) {
                        Text(translator.isQueued(summary.id) ? "번역 중 \(summary.translatedCount)/\(summary.sentenceCount)" : "번역 \(summary.translatedCount)/\(summary.sentenceCount)")
                    }
                    if !translator.isQueued(summary.id) {
                        Button("번역 이어서 하기") { translator.enqueue(bookID: summary.id) }
                            .buttonStyle(.borderless)
                    }
                    if let error = translator.lastError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .task(id: summary.id) {
                    await translator.checkPack(source: summary.language)
                }
            }
        }
    }

    private func rowDetail(_ summary: ImportedBookSummary) -> String {
        var parts = ["\(summary.chapterCount)개 장", "\(summary.sentenceCount)문장"]
        if !summary.isFullyTranslated {
            parts.append("번역 \(Int(summary.translationFraction * 100))%")
        }
        return parts.joined(separator: " · ")
    }

    private func requestPack(language: String) {
        let configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: language),
            target: BookTranslationService.targetLanguage
        )
        if packConfiguration == configuration {
            packConfiguration?.invalidate()
        } else {
            packConfiguration = configuration
        }
    }

    private func afterPackPrepared() async {
        guard let language = packConfiguration?.source?.languageCode?.identifier else { return }
        if await translator.checkPack(source: language) == .installed {
            translator.resumePending()
        }
    }
}

#Preview {
    NavigationStack {
        BookImportView(onOpen: { _ in })
    }
}
