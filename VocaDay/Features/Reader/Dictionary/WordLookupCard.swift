import SwiftData
import SwiftUI

// 리더 공통 계약 3: 단어 카드. 이니셜라이저 `init(context:book:)`은 계약 모양 그대로 둔다.

/// 단어를 누르면 뜨는 뜻 상자. 리더가 단어 옆 팝오버(폭 약 300pt)에 넣는다. 높이는 내용에 맞는다.
struct WordLookupCard: View {
    enum Phase: Equatable {
        case loading(String)
        case found(WordLookupResult)
        case notFound(WordLookupMiss)
    }

    let context: WordTapContext
    let book: BookDocument
    private let pipeline: WordLookupPipeline

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]
    @State private var pronunciation = WordPronunciationPlayer()
    @State private var phase: Phase
    @State private var saveError: String?

    init(context: WordTapContext, book: BookDocument) {
        self.init(context: context, book: book, pipeline: Self.pipeline(for: context.language))
    }

    /// 미리보기·테스트용. `initialPhase`를 주면 찾기를 건너뛴다.
    init(context: WordTapContext, book: BookDocument, pipeline: WordLookupPipeline, initialPhase: Phase? = nil) {
        self.context = context
        self.book = book
        self.pipeline = pipeline
        _phase = State(initialValue: initialPhase ?? .loading("뜻을 찾는 중…"))
    }

    /// 언어별 찾기 단계. 일본어 앱은 여기에 "ja" 단계를 넣는다.
    static func pipeline(for language: String) -> WordLookupPipeline {
        switch language.lowercased().prefix(2) {
        default: EnglishWordLookup.pipeline()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            meaningBox
            buttons
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(idealWidth: 300, maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: context.id) {
            guard case .loading = phase else { return }
            await runLookup()
        }
        .onDisappear { pronunciation.stop() }
    }

    // MARK: - 뜻 상자

    private var meaningBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headword)
                    .font(.title3.bold())
                    .textSelection(.enabled)
                if let partOfSpeech = meaningLines.partOfSpeech {
                    Text(partOfSpeech)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            switch phase {
            case .loading(let message):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(message)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            case .found(let result):
                ForEach(meaningLines.lines, id: \.self) { line in
                    Text(line)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = result.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(result.source.label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("출처: \(result.source.label)")
            case .notFound(let miss):
                Text("뜻을 찾지 못했어요")
                    .font(.body)
                if miss.needsGenerationConsent {
                    Button("기기 안에서 뜻 만들기") {
                        EnglishWordLookup.GenerationSettings.giveConsent()
                        Task { await runLookup() }
                    }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                    .help(miss.message)
                }
                Text("단어 추가 탭에서 직접 넣을 수 있어요")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous)
                .stroke(AppTheme.softStroke)
        }
    }

    private var headword: String {
        if case .found(let result) = phase { return result.headword }
        // 찾기 전에는 본문 모양 그대로 (고유명사 대문자 유지).
        return context.surface.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private var meaningLines: MeaningLines {
        guard case .found(let result) = phase else { return MeaningLines(partOfSpeech: nil, lines: []) }
        return MeaningLines(result)
    }

    // MARK: - 버튼 두 개

    private var buttons: some View {
        HStack(spacing: 8) {
            saveButton
            Button {
                Task { await pronunciation.speak(headword) }
            } label: {
                Label(
                    pronunciation.isPreparing ? "준비 중…" : "단어 듣기",
                    systemImage: pronunciation.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2"
                )
                .frame(maxWidth: .infinity)
            }
            .disabled(pronunciation.isPreparing)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .font(.subheadline.weight(.semibold))
    }

    @ViewBuilder
    private var saveButton: some View {
        if savedDayTitle != nil {
            Button {} label: {
                Label("저장됨", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .disabled(true)
            .accessibilityLabel("저장됨, \(savedDayTitle ?? "")")
        } else {
            Button {
                if let draft { save(draft) }
            } label: {
                Label("단어 저장", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .disabled(draft == nil)
        }
    }

    private var draft: VocaWordJSON? {
        guard case .found(let result) = phase else { return nil }
        return ReaderWordSaver.draft(for: result, context: context, book: book)
    }

    /// 이미 단어장에 있으면 그 데이 이름. 처음부터 「저장됨」으로 보인다.
    private var savedDayTitle: String? {
        guard let draft else { return nil }
        return ReaderWordSaver.existingDayTitle(for: draft.english, in: days)
    }

    /// 버튼 아래 한 줄: 저장 실패, 또는 저장 전 데이터 검사에 걸린 점.
    private var notice: String? {
        if let saveError { return saveError }
        guard savedDayTitle == nil, let draft else { return nil }
        return ReaderWordSaver.issues(for: draft).lazy.compactMap(Self.shortNotice).first
    }

    /// 상자 아래에 맞게 줄인 검사 문구. 예문 번역이 없는 것은 알리지 않는다 (권장 항목).
    static func shortNotice(_ issue: WordDataCheck.Issue) -> String? {
        switch issue {
        case .missingMeaning: "뜻이 없어 저장할 수 없어요"
        case .missingExample, .exampleMissingWord: "문장에 단어 모양이 달라 빈칸 문제는 빠져요"
        case .someExampleLinesMissingWord, .exampleTranslationLineMismatch, .missingExampleTranslation: nil
        }
    }

    private func save(_ draft: VocaWordJSON) {
        do {
            try ReaderWordSaver.add(draft, existingDays: days, in: modelContext)
            saveError = nil
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runLookup() async {
        phase = .loading("뜻을 찾는 중…")
        let outcome = await pipeline.lookup(context, book: book) { message in
            phase = .loading(message)
        }
        switch outcome {
        case .found(let result): phase = .found(result)
        case .notFound(let miss): phase = .notFound(miss)
        }
    }
}

/// 상자에 보일 뜻 줄. 품사가 하나면 단어 옆에, 여럿이면 줄마다 앞에 붙인다. 최대 3줄.
struct MeaningLines: Equatable {
    var partOfSpeech: String?
    var lines: [String]

    init(partOfSpeech: String?, lines: [String]) {
        self.partOfSpeech = partOfSpeech
        self.lines = lines
    }

    init(_ result: WordLookupResult) {
        if let pos = result.partOfSpeech, !pos.isEmpty {
            self.init(partOfSpeech: pos, lines: [result.meaning])
            return
        }
        // "n. 검토, 평가 / v. 검토하다" · "v. 할당하다, n. 할당" → 품사 표시마다 나눈다.
        let marker = #"(?<![A-Za-z])(n|v|vt|vi|adj|adv|phr|prep|conj|pron|interj|int|idiom|aux)\.\s*"#
        let meaning = result.meaning
        guard let regex = try? NSRegularExpression(pattern: marker, options: [.caseInsensitive]) else {
            self.init(partOfSpeech: nil, lines: [meaning])
            return
        }
        let matches = regex.matches(in: meaning, range: NSRange(meaning.startIndex..., in: meaning))
        guard !matches.isEmpty else {
            self.init(partOfSpeech: nil, lines: [meaning])
            return
        }
        var segments: [(pos: String, text: String)] = []
        for (index, match) in matches.enumerated() {
            guard let posRange = Range(match.range(at: 1), in: meaning),
                  let start = Range(match.range, in: meaning)?.upperBound else { continue }
            let end = index + 1 < matches.count
                ? (Range(matches[index + 1].range, in: meaning)?.lowerBound ?? meaning.endIndex)
                : meaning.endIndex
            let text = meaning[start..<end]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",/;")))
            segments.append((meaning[posRange].lowercased() + ".", text))
        }
        if segments.count == 1, let only = segments.first {
            self.init(partOfSpeech: only.pos, lines: [only.text])
        } else {
            self.init(partOfSpeech: nil, lines: segments.prefix(3).map { "\($0.pos) \($0.text)" })
        }
    }
}

/// 문장에서 누른 단어를 찾아 강조한다. 같은 모양이 여럿이면 처음 것만. (미리보기 문장 고르기에도 쓴다)
enum WordHighlighter {
    static func highlighted(_ surface: String, in sentence: String) -> AttributedString {
        var text = AttributedString(sentence)
        guard let range = range(of: surface, in: sentence),
              let lower = AttributedString.Index(range.lowerBound, within: text),
              let upper = AttributedString.Index(range.upperBound, within: text)
        else { return text }
        text[lower..<upper].font = .body.bold()
        text[lower..<upper].foregroundColor = .accentColor
        text[lower..<upper].underlineStyle = .single
        return text
    }

    /// 단어 경계로 찾는다 (review가 preview 안에서 걸리지 않게).
    static func range(of surface: String, in sentence: String) -> Range<String.Index>? {
        let word = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: word) + "(?![A-Za-z])"
        return sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive])
    }
}

#Preview("책 사전 · 원형") {
    let book = WordLookupCardPreview.book
    let context = WordLookupCardPreview.context(surface: "allocated", book: book)
    return WordLookupCard(context: context, book: book)
        .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}

#Preview("못 찾음") {
    let book = WordLookupCardPreview.book
    let context = WordLookupCardPreview.context(surface: "Mina", book: book)
    return WordLookupCard(
        context: context,
        book: book,
        pipeline: EnglishWordLookup.pipeline(),
        initialPhase: .notFound(WordLookupMiss(message: "책 사전과 기본 단어장에 없는 단어예요."))
    )
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}

/// 미리보기용 샘플 책 (Resources/Books/sample-first-week.json).
enum WordLookupCardPreview {
    static var book: BookDocument {
        guard let url = Bundle.main.url(forResource: "sample-first-week", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let book = try? JSONDecoder().decode(BookDocument.self, from: data)
        else {
            return BookDocument(
                formatVersion: 1, id: "preview", language: "en", title: "Preview",
                subtitle: nil, author: nil, level: nil, summary: nil,
                chapters: [BookChapter(title: "", paragraphs: [BookParagraph(sentences: [
                    BookSentence(text: "Her manager had already allocated a desk near the window for her.", translation: "그녀의 매니저는 이미 창가 근처 책상을 그녀에게 배정해 두었다."),
                ])])],
                glossary: []
            )
        }
        return book
    }

    /// 본문에서 `surface`가 처음 나오는 문장으로 누른 값을 만든다.
    static func context(surface: String, book: BookDocument) -> WordTapContext {
        let position = book.positions.first { position in
            book.sentence(at: position).map { WordHighlighter.range(of: surface, in: $0.text) != nil } ?? false
        } ?? .start
        let sentence = book.sentence(at: position)
        return WordTapContext(
            surface: surface,
            bookID: book.id,
            language: book.language,
            position: position,
            sentence: sentence?.text ?? "",
            sentenceTranslation: sentence?.translation
        )
    }
}
