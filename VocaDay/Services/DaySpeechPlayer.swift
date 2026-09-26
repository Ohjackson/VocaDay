import AVFoundation
import Combine
import Foundation

@MainActor
final class DaySpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isPlaying = false
    /// 지금 읽고 있는 단어. 목록에서 강조할 때 쓴다.
    @Published private(set) var currentWordID: UUID?

    private let speechRate = AVSpeechUtteranceDefaultSpeechRate * 0.8
    private let singleWordSpeechRate = AVSpeechUtteranceDefaultSpeechRate * 0.72
    private let synthesizer = AVSpeechSynthesizer()
    private var playbackTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(words: [VocaWord], completion: @escaping @MainActor () -> Void) {
        stop()
        guard !words.isEmpty else { return }

        isPlaying = true
        playbackTask = Task { @MainActor in
            for (index, word) in words.enumerated() {
                guard !Task.isCancelled else { break }
                currentWordID = word.id
                await speak(englishNumber(index + 1), language: "en-US")

                guard !Task.isCancelled else { break }
                await speak(word.english, language: "en-US")
                await speak(word.english, language: "en-US")

                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(2))
                await speak(word.meaningKo, language: "ko-KR")

                // 예문이 여러 줄이면 번호 없이 줄마다 영어 → 번역 순서로 읽는다.
                for example in ExamText.examplePairs(en: word.exampleEn, ko: word.exampleKo) {
                    guard !Task.isCancelled else { break }
                    if !example.en.isEmpty {
                        await speak(example.en, language: "en-US")
                    }

                    guard !Task.isCancelled else { break }
                    if !example.ko.isEmpty {
                        try? await Task.sleep(for: .seconds(2))
                        await speak(example.ko, language: "ko-KR")
                    }
                }
            }

            let wasCancelled = Task.isCancelled
            stop()

            if !wasCancelled {
                completion()
            }
        }
    }

    func speakEnglishWord(_ english: String, wordID: UUID? = nil) {
        speakEnglish(english, wordID: wordID, rate: singleWordSpeechRate)
    }

    /// 예문처럼 긴 영어 문장. 단어보다 조금 빠른 문장 속도로 읽는다.
    func speakEnglishSentence(_ sentence: String) {
        speakEnglish(sentence, wordID: nil, rate: speechRate)
    }

    private func speakEnglish(_ english: String, wordID: UUID?, rate: Float) {
        stop()

        let trimmed = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isPlaying = true
        currentWordID = wordID
        playbackTask = Task { @MainActor in
            await speak(trimmed, language: "en-US", rate: rate)
            stop()
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        continuation?.resume()
        continuation = nil
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        currentWordID = nil
    }

    private func speak(_ text: String, language: String, rate: Float? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = preferredVoice(for: language)
            utterance.rate = rate ?? speechRate
            utterance.pitchMultiplier = 1
            utterance.preUtteranceDelay = 0.08
            utterance.postUtteranceDelay = 0.14
            utterance.volume = 1
            synthesizer.speak(utterance)
        }
    }

    private func preferredVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return voices.first { $0.quality == .premium }
            ?? voices.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    private func englishNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            continuation?.resume()
            continuation = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            continuation?.resume()
            continuation = nil
        }
    }
}
