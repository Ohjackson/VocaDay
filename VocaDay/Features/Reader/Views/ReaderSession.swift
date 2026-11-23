import Foundation
import Observation

/// 본문 안 단어 하나의 자리. 같은 문장에 같은 단어가 두 번 나와도 구분한다.
nonisolated struct ReaderTokenRef: Hashable, Sendable {
    var position: ReadingPosition
    var index: Int
}

/// 지금 열려 있는 단어 카드.
nonisolated struct ReaderActiveWord: Identifiable, Hashable, Sendable {
    var ref: ReaderTokenRef
    var context: WordTapContext
    var id: String { "\(context.id)#\(ref.index)" }
}

/// 책 한 권을 읽는 동안의 상태. 위치·재생·단어 카드·북마크를 한곳에서 바꾼다.
/// 위치는 바뀔 때마다 `ReadingStore.saveLastPosition` 으로 남긴다.
@Observable
final class ReaderSession {
    struct ScrollRequest: Equatable {
        var position: ReadingPosition
        var serial: Int
    }

    let book: BookDocument
    let navigator: ReadingNavigator
    let speaker = SentenceSpeaker()

    private(set) var position: ReadingPosition
    /// 값이 바뀌면 본문이 이 위치로 스크롤한다.
    private(set) var scrollRequest: ScrollRequest
    var activeWord: ReaderActiveWord?
    /// 번역을 펼친 문장. 페이지 나누기가 흔들리지 않게 본문 안이 아니라 아래 띠에 보여 준다.
    private(set) var translationPosition: ReadingPosition?
    private(set) var voice = ListeningVoice.fallback
    private(set) var speed = 1.0

    @ObservationIgnored private let store: any ReadingStore
    @ObservationIgnored private let sentenceTexts: [String]
    /// 스크롤로 위치를 옮기지 않는 시각. 코드로 스크롤하는 동안 지나가는 페이지를 위치로 삼지 않으려는 것이다.
    @ObservationIgnored private var ignoresVisiblePagesUntil: Date
    @ObservationIgnored private let now: () -> Date

    init(book: BookDocument, store: any ReadingStore, now: @escaping () -> Date = Date.init) {
        self.book = book
        self.store = store
        self.now = now
        let navigator = ReadingNavigator(book: book)
        self.navigator = navigator
        sentenceTexts = navigator.positions.map { book.sentence(at: $0)?.text ?? "" }
        let start = navigator.resolve(store.lastPosition(bookID: book.id))
        position = start
        scrollRequest = ScrollRequest(position: start, serial: 0)
        ignoresVisiblePagesUntil = now().addingTimeInterval(1.2)
        WordLookupWarmUp.start()
        speaker.onSentenceChange = { [weak self] index in
            guard let self, let index, self.navigator.positions.indices.contains(index) else { return }
            self.setPosition(self.navigator.positions[index], scroll: true)
        }
    }

    // MARK: 위치

    var isSpeaking: Bool { speaker.isSpeaking }

    /// 소리가 나는 문장. 재생 중이 아니면 nil.
    var speakingPosition: ReadingPosition? {
        guard speaker.isSpeaking, let index = speaker.currentIndex, navigator.positions.indices.contains(index) else { return nil }
        return navigator.positions[index]
    }

    /// 읽은 정도 (0…1).
    var progress: Double { navigator.progress(of: position) }

    var currentChapterTitle: String {
        book.chapters.indices.contains(position.chapter) ? book.chapters[position.chapter].title : ""
    }

    /// 목차·북마크·이전/다음에서 옮길 때. 재생 중이면 그 문장부터 이어 읽는다.
    func jump(to target: ReadingPosition) {
        let resolved = navigator.resolve(target)
        if isSpeaking {
            play(from: resolved)
        } else {
            setPosition(resolved, scroll: true)
        }
    }

    func goNext() {
        if let next = navigator.next(after: position) { jump(to: next) }
    }

    func goPrevious() {
        if let previous = navigator.previous(before: position) { jump(to: previous) }
    }

    var canGoNext: Bool { navigator.next(after: position) != nil }
    var canGoPrevious: Bool { navigator.previous(before: position) != nil }

    /// 스크롤해서 보이는 페이지가 바뀌었을 때. 각 원소는 보이는 페이지 하나의 문장들(위 페이지부터).
    /// 읽던 문장이 보이는 페이지에 없으면 맨 위 페이지의 첫 문장을 위치로 삼는다.
    func noteVisiblePages(_ pages: [[ReadingPosition]]) {
        guard !isSpeaking, now() >= ignoresVisiblePagesUntil else { return }
        let pages = pages.filter { !$0.isEmpty }
        guard let top = pages.first?.first, !pages.contains(where: { $0.contains(position) }) else { return }
        setPosition(top, scroll: false)
    }

    private func setPosition(_ newPosition: ReadingPosition, scroll: Bool) {
        if newPosition != position {
            position = newPosition
            store.saveLastPosition(newPosition, bookID: book.id)
        }
        if scroll {
            ignoresVisiblePagesUntil = now().addingTimeInterval(0.8)
            scrollRequest = ScrollRequest(position: newPosition, serial: scrollRequest.serial + 1)
        }
    }

    // MARK: 듣기

    func togglePlayback() {
        if isSpeaking {
            speaker.stop()
        } else {
            play(from: position)
        }
    }

    func play(from start: ReadingPosition) {
        let resolved = navigator.resolve(start)
        guard let index = navigator.index(of: resolved) else { return }
        setPosition(resolved, scroll: true)
        speaker.play(sentenceTexts, from: index, voice: voice, speed: Float(speed))
    }

    func stop() {
        speaker.stop()
    }

    /// 재생 중에 바꾸면 지금 문장부터 새 설정으로 다시 읽는다.
    func setVoice(_ newVoice: ListeningVoice) {
        guard newVoice != voice else { return }
        voice = newVoice
        restartIfSpeaking()
    }

    func setSpeed(_ newSpeed: Double) {
        guard newSpeed != speed else { return }
        speed = newSpeed
        restartIfSpeaking()
    }

    private func restartIfSpeaking() {
        guard isSpeaking else { return }
        play(from: speakingPosition ?? position)
    }

    // MARK: 단어·문장

    /// 단어를 눌렀다. 단어 카드만 연다. 읽는 위치는 옮기지 않는다 (마일드 화면: 누른 단어 외에는 아무것도 바뀌지 않는다).
    func tapWord(_ surface: String, ref: ReaderTokenRef) {
        guard let sentence = book.sentence(at: ref.position) else { return }
        activeWord = ReaderActiveWord(
            ref: ref,
            context: WordTapContext(
                surface: surface,
                bookID: book.id,
                language: book.language,
                position: ref.position,
                sentence: sentence.text,
                sentenceTranslation: sentence.translation
            )
        )
    }

    func isTranslationRevealed(at position: ReadingPosition) -> Bool {
        translationPosition == position
    }

    func toggleTranslation(at position: ReadingPosition) {
        translationPosition = translationPosition == position ? nil : position
    }

    func hideTranslation() {
        translationPosition = nil
    }

    // MARK: 북마크

    var bookmarks: [ReaderBookmark] { store.bookmarks(bookID: book.id) }

    func bookmark(at position: ReadingPosition) -> ReaderBookmark? {
        bookmarks.first { $0.position == position }
    }

    func toggleBookmark(at position: ReadingPosition) {
        if let existing = bookmark(at: position) {
            store.removeBookmark(id: existing.id)
        } else {
            store.addBookmark(at: position, bookID: book.id, note: "")
        }
    }

    func removeBookmark(_ bookmark: ReaderBookmark) {
        store.removeBookmark(id: bookmark.id)
    }
}
