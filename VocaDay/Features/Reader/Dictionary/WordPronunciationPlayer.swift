import Combine
import Foundation
import Observation

/// 카드의 발음 듣기. 리스닝의 Kokoro 재생(`ListeningPlayer`)으로 단어만 읽는다.
/// Kokoro를 쓸 수 없는 환경(iOS 시뮬레이터, 모델 파일 없음)에서는 시스템 음성으로 읽는다.
@MainActor
@Observable
final class WordPronunciationPlayer {
    enum Engine: Equatable {
        case kokoro
        case system
    }

    private(set) var isPreparing = false
    /// 마지막으로 읽은 엔진. 시스템 음성으로 읽었으면 카드에 작게 알린다.
    private(set) var engine: Engine?
    /// 시스템 음성(`DaySpeechPlayer`, ObservableObject)의 재생 상태를 옮겨 둔다.
    private var systemIsPlaying = false

    var isSpeaking: Bool { kokoro.isSpeaking || systemIsPlaying }

    /// 리스닝 탭에서 고른 보이스를 그대로 쓴다.
    static let voiceKey = "listeningVoiceID"
    /// 단어 하나는 문장보다 조금 천천히.
    static let speed: Float = 0.9

    @ObservationIgnored private let kokoro: ListeningPlayer
    @ObservationIgnored private let system = DaySpeechPlayer()
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    init(kokoro: ListeningPlayer = ListeningPlayer()) {
        self.kokoro = kokoro
        system.$isPlaying
            .removeDuplicates()
            .sink { [weak self] in self?.systemIsPlaying = $0 }
            .store(in: &cancellables)
    }

    func speak(_ word: String) async {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPreparing else { return }
        stop()
        isPreparing = true
        await kokoro.prepare()
        isPreparing = false
        if kokoro.modelState == .ready {
            engine = .kokoro
            let voiceID = UserDefaults.standard.string(forKey: Self.voiceKey) ?? ListeningVoice.fallback.id
            kokoro.speak(trimmed, voice: ListeningVoice.voice(id: voiceID), speed: Self.speed)
        } else {
            engine = .system
            system.speakEnglishWord(trimmed)
        }
    }

    func stop() {
        kokoro.stop()
        system.stop()
    }
}
