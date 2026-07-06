import AVFoundation
import Combine
import Foundation

@MainActor
final class DaySpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isPlaying = false

    private let speechRate = AVSpeechUtteranceDefaultSpeechRate * 0.8
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
                await speak(englishNumber(index + 1), language: "en-US")

                guard !Task.isCancelled else { break }
                await speak(word.english, language: "en-US")
                await speak(word.english, language: "en-US")

                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(2))
                await speak(word.meaningKo, language: "ko-KR")

                guard !Task.isCancelled else { break }
                await speak(word.exampleEn, language: "en-US")

                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(2))
                await speak(word.exampleKo, language: "ko-KR")
            }

            let wasCancelled = Task.isCancelled
            stop()

            if !wasCancelled {
                completion()
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        continuation?.resume()
        continuation = nil
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
    }

    private func speak(_ text: String, language: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = preferredVoice(for: language)
            utterance.rate = speechRate
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
