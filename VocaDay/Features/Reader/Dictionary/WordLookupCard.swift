import SwiftData
import SwiftUI
import Translation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    private let generation: GeneratedWordLookupStep?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]
    @State private var pronunciation = WordPronunciationPlayer()
    @State private var phase: Phase
    @State private var saveError: String?
    @State private var showsSystemDictionary = false
    @State private var copiedPrompt = false
    /// 기기 사전에 이 단어가 있는지. nil = 아직 확인 전.
    @State private var systemDictionaryHasEntry: Bool?
    #if os(iOS)
    /// 카드 안 사전에 넘길 말. 사전에 없으면 nil (줄을 보이지 않는다).
    @State private var inlineDictionaryTerm: String?
    @State private var showsInlineDictionary = false
    #else
    /// 사전 글을 품사·뜻·예문으로 나눈 것.
    @State private var dictionaryArticle: SystemDictionaryArticle?
    @State private var showsAllSenses = false
    #endif
    /// 영→한 번역 언어 팩을 받을 수 있는데 아직 없다. 한국어 뜻 대신 영영 뜻이나 "없음"이 나올 때 받기 버튼을 보인다.
    @State private var canDownloadKoreanPack = false
    @State private var packConfiguration: TranslationSession.Configuration?
    /// 카드 내용의 실제 높이. 팝오버가 이 높이를 원하게 한다.
    @State private var contentHeight: CGFloat = 160
    @Environment(\.openURL) private var openURL

    init(context: WordTapContext, book: BookDocument) {
        self.init(
            context: context,
            book: book,
            pipeline: context.isPhrase ? EnglishWordLookup.phrasePipeline() : Self.pipeline(for: context.language),
            // 여러 단어는 기기 생성(단어 하나용)을 쓰지 않는다.
            generation: context.isPhrase ? nil : Self.generation(for: context.language)
        )
    }

    /// 미리보기·테스트용. `initialPhase`를 주면 찾기를 건너뛴다.
    init(
        context: WordTapContext,
        book: BookDocument,
        pipeline: WordLookupPipeline,
        generation: GeneratedWordLookupStep? = nil,
        initialPhase: Phase? = nil
    ) {
        self.context = context
        self.book = book
        self.pipeline = pipeline
        self.generation = generation
        _phase = State(initialValue: initialPhase ?? .loading("뜻을 찾는 중…"))
    }

    /// 언어별 자동 찾기(JSON 데이터). 일본어 앱은 여기에 "ja" 단계를 넣는다.
    static func pipeline(for language: String) -> WordLookupPipeline {
        switch language.lowercased().prefix(2) {
        default: EnglishWordLookup.pipeline()
        }
    }

    /// 「⋯ → 기기에서 뜻 만들기」. 그 언어에 생성이 없으면 nil (메뉴에서 빠진다).
    static func generation(for language: String) -> GeneratedWordLookupStep? {
        switch language.lowercased().prefix(2) {
        default: EnglishWordLookup.generation()
        }
    }

    var body: some View {
        // 뜻이 길어 화면에 다 안 들어가면 팝오버가 내용을 잘라 위쪽(표제어)이 사라졌다.
        // 내용 높이를 재서 그만큼을 원하되, 자리가 모자라면 잘리지 않고 스크롤된다.
        ScrollView {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: 300, maxWidth: .infinity, idealHeight: cardHeight, maxHeight: cardHeight)
        .task(id: context.id) {
            guard case .loading = phase else { return }
            await runLookup()
        }
        .task(id: dictionaryTerm) {
            // 기기 사전 확인(특히 iOS)은 메인 스레드에서 오래 걸린다. 뜻이 먼저 그려지게 조금 미루고, 결과는 기억한다.
            if case .loading = phase { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            let found = [dictionaryTerm, context.surface].first { SystemDictionary.cachedHasDefinition(for: $0) }
            systemDictionaryHasEntry = found != nil
            #if os(iOS)
            inlineDictionaryTerm = found
            #else
            dictionaryArticle = found.flatMap { SystemDictionary.article(for: $0) }
            #endif
        }
        .background {
            // 언어 팩이 없으면 시스템이 받기 안내를 띄운다. 받고 나면 한국어 뜻으로 다시 찾는다.
            // 시스템 창은 기기 모드로 그려지므로, 책 테마(세피아 등)가 아니라 기기 모드를 넘겨야 글자가 보인다.
            Color.clear
                .translationTask(packConfiguration) { session in
                    do { try await session.prepareTranslation() } catch {}
                    await checkKoreanPack()
                    if !canDownloadKoreanPack { await runLookup() }
                }
                .environment(\.colorScheme, SystemDictionary.deviceColorScheme)
        }
        .onDisappear { pronunciation.stop() }
        #if os(iOS)
        .sheet(isPresented: $showsSystemDictionary) {
            SystemDictionarySheet(term: dictionaryTerm)
                .ignoresSafeArea()
                .environment(\.colorScheme, SystemDictionarySheet.deviceColorScheme)
                .preferredColorScheme(SystemDictionarySheet.deviceColorScheme)
        }
        #endif
    }

    // MARK: - 뜻 상자

    private var meaningBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if context.isPhrase {
                    Label("구절 번역", systemImage: "text.quote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Button(action: openSystemDictionary) {
                        Text(headword)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(headword), 사전에서 보기")
                    .help("사전에서 보기")
                }
                if let partOfSpeech = meaningLines.partOfSpeech {
                    Text(partOfSpeech)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if !context.isPhrase { dictionaryBadge }
                moreMenu
            }
            switch phase {
            case .loading(let message):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(message)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            case .found(let result) where context.isPhrase:
                phraseBody(translation: result.meaning, note: result.note)
                if canDownloadKoreanPack { koreanPackButton }
            case .notFound where context.isPhrase:
                phraseBody(translation: nil, note: nil)
                Text("이 말을 번역하지 못했어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if canDownloadKoreanPack { koreanPackButton }
            case .found(let result):
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(meaningLines.lines, id: \.self) { line in
                        meaningRow(line)
                    }
                }
                if let note = result.note, !note.isEmpty {
                    Label {
                        Text(note)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lightbulb")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if let tag = result.toeicTag, !tag.isEmpty {
                    Text(tag)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.12), in: Capsule())
                }
                // 만든 뜻은 틀릴 수 있어 출처를 남긴다.
                if result.source == .generated {
                    Text(result.source.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("출처: \(result.source.label)")
                }
                if canDownloadKoreanPack { koreanPackButton }
            case .notFound(let miss):
                Text(miss.message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("단어를 누르면 사전, ⋯에서 기기 생성·AI에 묻기")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if canDownloadKoreanPack { koreanPackButton }
            }
            if !context.isPhrase, !isLoading { dictionarySection }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 끌어 고른 구절: 영어 구절 → 한국어 번역.
    @ViewBuilder
    private func phraseBody(translation: String?, note: String?) -> some View {
        Text(context.surface)
            .font(.title3.weight(.semibold))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        if let translation {
            Text(translation)
                .font(.body)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let note, !note.isEmpty {
            Label(note, systemImage: "lightbulb")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "v. 협상하다" → 품사 칩 + 뜻. 품사가 없으면 뜻만.
    @ViewBuilder
    private func meaningRow(_ line: String) -> some View {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].hasSuffix("."), parts[0].count <= 7 {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parts[0])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(parts[1])
                    .font(.body)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(line)
                .font(.body)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headword: String {
        if context.isPhrase { return context.surface }
        if case .found(let result) = phase { return result.headword }
        // 찾기 전에는 본문 모양 그대로 (고유명사 대문자 유지).
        return context.surface.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private var meaningLines: MeaningLines {
        guard case .found(let result) = phase, !repeatsArticle(result) else { return MeaningLines(partOfSpeech: nil, lines: []) }
        return MeaningLines(result)
    }

    /// 뜻이 사전 글의 첫 줄이면 아래 사전과 겹치므로 따로 보이지 않는다 (Mac).
    private func repeatsArticle(_ result: WordLookupResult) -> Bool {
        #if os(macOS)
        result.source == .systemDictionary && dictionaryArticle != nil
        #else
        false
        #endif
    }

    /// 카드 높이. Mac은 사전 글이 길어도 이만큼까지만 커지고 안에서 스크롤된다.
    private var cardHeight: CGFloat {
        #if os(macOS)
        min(contentHeight, 440)
        #else
        contentHeight
        #endif
    }

    // MARK: - 기기 사전

    #if os(iOS)
    /// 누르면 카드 안에서 사전을 펼친다. 사전 글을 꺼내는 API가 없어 사전 화면을 그대로 넣는다.
    @ViewBuilder
    private var dictionarySection: some View {
        if let term = inlineDictionaryTerm {
            Divider().padding(.top, 2)
            Button {
                showsInlineDictionary.toggle()
            } label: {
                HStack {
                    Text(showsInlineDictionary ? "기기 사전 접기" : "기기 사전에서 더 보기")
                        .font(.subheadline)
                    Spacer(minLength: 4)
                    Image(systemName: showsInlineDictionary ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.tint)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsInlineDictionary {
                InlineSystemDictionary(term: term)
                    .id(term)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    #else
    private static let shortSenseCount = 3

    /// 사전 글: 품사마다 뜻과 예문. 길면 품사마다 앞의 몇 개만 보이고 「더 보기」로 편다.
    @ViewBuilder
    private var dictionarySection: some View {
        if let article = dictionaryArticle {
            let short = article.prefix(Self.shortSenseCount)
            let hiddenCount = article.senseCount - short.reduce(0) { $0 + $1.senses.count }
            if !meaningLines.lines.isEmpty { Divider().padding(.vertical, 2) }
            ForEach(Array((showsAllSenses ? article.sections : short).enumerated()), id: \.offset) { _, section in
                if let partOfSpeech = section.partOfSpeech {
                    Text(partOfSpeech)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.top, 2)
                }
                ForEach(Array(section.senses.enumerated()), id: \.offset) { _, sense in
                    senseRow(sense)
                }
            }
            if hiddenCount > 0 {
                Button(showsAllSenses ? "접기" : "뜻 \(hiddenCount)개 더 보기") {
                    showsAllSenses.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private func senseRow(_ sense: SystemDictionaryArticle.Sense) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(sense.number ?? "•")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 12, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(sense.text)
                    .font(.callout)
                ForEach(sense.examples.prefix(2), id: \.self) { example in
                    Text(example)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
    }
    #endif

    // MARK: - 사전 표시 (오른쪽 위)

    /// 기기 사전에 단어가 있으면 사전 아이콘, 없으면 ✕가 붙은 아이콘. 누르면 사전을 연다
    /// (없을 때도 사전 화면에서 사전을 내려받을 수 있다).
    private var dictionaryBadge: some View {
        let missing = systemDictionaryHasEntry == false
        return Button(action: openSystemDictionary) {
            Image(systemName: "character.book.closed")
                .font(.body)
                .foregroundStyle(missing ? .tertiary : .secondary)
                .overlay(alignment: .bottomTrailing) {
                    if missing {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red.opacity(0.85))
                            .background(Circle().fill(AppTheme.cardBackground).padding(1))
                            .offset(x: 4, y: 3)
                    }
                }
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(systemDictionaryHasEntry == nil ? 0 : 1)
        .accessibilityLabel(missing ? "기기 사전에 없는 단어, 사전 열기" : "사전에서 보기")
        .help(missing ? "기기 사전에 없는 단어예요" : "사전에서 보기")
    }

    // MARK: - ⋯ 메뉴

    private var moreMenu: some View {
        Menu {
            Button(action: openSystemDictionary) {
                Label("사전에서 보기", systemImage: "character.book.closed")
            }
            if let generation {
                let reason = generation.unavailableReason
                Button {
                    Task { await runGeneration(generation) }
                } label: {
                    Label {
                        Text("기기에서 뜻 만들기")
                        if let reason { Text(Self.shortReason(reason)) }
                    } icon: {
                        Image(systemName: "apple.intelligence")
                    }
                }
                .disabled(reason != nil || isLoading)
            }
            Section {
                ForEach(WordAskPrompt.Destination.allCases, id: \.self) { destination in
                    Button {
                        if let url = askPrompt.url(for: destination) { openURL(url) }
                    } label: {
                        Label(destination.title, systemImage: "bubble.left.and.text.bubble.right")
                    }
                }
                Button(action: copyPrompt) {
                    Label(copiedPrompt ? "복사했어요" : "질문 복사", systemImage: "doc.on.doc")
                }
                ShareLink(item: askPrompt.text) {
                    Label("질문 공유", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("더 보기")
    }

    /// 메뉴 항목 아래 한 줄 이유.
    static func shortReason(_ reason: EnglishWordGenerationUnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "이 기기는 Apple Intelligence를 지원하지 않아요"
        case .appleIntelligenceNotEnabled: "Apple Intelligence가 꺼져 있어요"
        case .modelNotReady: "기기 모델을 준비하는 중이에요"
        case .disabledInSettings: "설정 > 단어 추가에서 꺼져 있어요"
        }
    }

    private var askPrompt: WordAskPrompt { WordAskPrompt(context) }

    /// 사전에 넘길 말. 찾은 원형이 있으면 그것, 없으면 본문 모양.
    private var dictionaryTerm: String {
        headword
    }

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    private func openSystemDictionary() {
        #if os(iOS)
        showsSystemDictionary = true
        #else
        if let url = SystemDictionary.url(for: dictionaryTerm) { openURL(url) }
        #endif
    }

    private func copyPrompt() {
        #if os(iOS)
        UIPasteboard.general.string = askPrompt.text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(askPrompt.text, forType: .string)
        #endif
        copiedPrompt = true
    }

    // MARK: - 버튼 두 개

    private var buttons: some View {
        HStack(spacing: 8) {
            saveButton
            Button {
                Task { await pronunciation.speak(headword) }
            } label: {
                Label(
                    pronunciation.isPreparing ? "준비 중…" : (context.isPhrase ? "듣기" : "단어 듣기"),
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
                Label(context.isPhrase ? "표현 저장" : "단어 저장", systemImage: "plus").frame(maxWidth: .infinity)
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

    private func runGeneration(_ generation: GeneratedWordLookupStep) async {
        EnglishWordLookup.GenerationSettings.giveConsent()
        let previous = phase
        phase = .loading(generation.progressMessage ?? "뜻을 만드는 중…")
        let request = pipeline.request(for: context, book: book)
        do {
            if let result = try await generation.lookup(request) {
                // 새로 만든 뜻이 전에 찾은 뜻을 대신한다.
                remember(result)
                phase = .found(result)
            } else {
                phase = previous
            }
        } catch let failure as WordLookupStepFailure {
            phase = .notFound(failure.miss)
        } catch {
            phase = .notFound(WordLookupMiss(message: "기기 안에서 뜻을 만들지 못했어요."))
        }
    }

    /// 이번 실행에서 찾은 뜻. 같은 문장의 같은 단어를 다시 누르면 바로 보인다.
    private static var foundCache: [String: WordLookupResult] = [:]

    private var cacheKey: String { "\(context.bookID)|\(context.surface.lowercased())|\(context.sentence)" }

    /// 영영사전 글은 남기지 않는다. 번역 언어 팩을 받은 뒤에는 한국어 뜻으로 다시 찾아야 한다.
    private func remember(_ result: WordLookupResult) {
        guard result.source != .systemDictionary else { return }
        Self.foundCache[cacheKey] = result
    }

    private func runLookup() async {
        if let cached = Self.foundCache[cacheKey] {
            phase = .found(cached)
            await checkKoreanPack()
            return
        }
        phase = .loading("뜻을 찾는 중…")
        let outcome = await pipeline.lookup(context, book: book) { message in
            phase = .loading(message)
        }
        switch outcome {
        case .found(let result):
            remember(result)
            phase = .found(result)
        case .notFound(let miss): phase = .notFound(miss)
        }
        await checkKoreanPack()
    }

    // MARK: - 한국어 뜻 (번역 언어 팩)

    /// 한국어 뜻이 아닌 결과(영영사전·없음)일 때만 언어 팩 상태를 본다.
    private func checkKoreanPack() async {
        let needsKorean: Bool
        switch phase {
        case .found(let result): needsKorean = result.source == .systemDictionary
        case .notFound: needsKorean = true
        case .loading: needsKorean = false
        }
        guard needsKorean, context.language.lowercased().hasPrefix("en") else {
            canDownloadKoreanPack = false
            return
        }
        let status = await LanguageAvailability().status(
            from: TranslationWordLookupStep.source, to: TranslationWordLookupStep.target
        )
        canDownloadKoreanPack = status == .supported
    }

    private var koreanPackButton: some View {
        Button {
            let configuration = TranslationSession.Configuration(
                source: TranslationWordLookupStep.source, target: TranslationWordLookupStep.target
            )
            if packConfiguration == configuration {
                packConfiguration?.invalidate()
            } else {
                packConfiguration = configuration
            }
        } label: {
            Label("한국어 뜻 보기 · 번역 언어 팩 받기", systemImage: "arrow.down.circle")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .padding(.top, 2)
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
