import Foundation
import NaturalLanguage
import Observation

/// 직접 넣은 글 듣기의 재생 상태. 글을 문장으로 나눠 `SentenceSpeaker`로 한 문장씩 읽는다.
/// 첫 문장만 만들어지면 바로 듣기 시작하고, 다음 문장은 읽는 동안 미리 만든다.
@Observable
final class ListeningPlayer {
    typealias ModelState = SentenceSpeaker.ModelState

    private(set) var sentences: [String] = []
    @ObservationIgnored private let speaker = SentenceSpeaker()

    var modelState: ModelState { speaker.modelState }
    var isSpeaking: Bool { speaker.isSpeaking }
    var currentSentence: Int? { speaker.currentIndex }
    var stats: String { speaker.stats }

    func prepare() async {
        await speaker.prepare()
    }

    func speak(_ text: String, voice: ListeningVoice, speed: Float) {
        sentences = Self.splitSentences(text)
        speaker.play(sentences, from: 0, voice: voice, speed: speed)
    }

    /// 지금 글의 한 문장부터 다시 읽는다.
    func replay(from index: Int, voice: ListeningVoice, speed: Float) {
        speaker.play(sentences, from: index, voice: voice, speed: speed)
    }

    func stop() {
        speaker.stop()
    }

    static func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
