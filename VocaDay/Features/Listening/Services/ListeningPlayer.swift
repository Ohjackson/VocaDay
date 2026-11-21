import AVFoundation
import Combine
import Foundation
import NaturalLanguage

/// 리스닝 화면의 재생 상태. 글을 문장으로 나눠 한 문장씩 만들고, 만들어지는 대로 바로 재생한다.
/// 그래서 긴 글도 첫 문장만 기다리면 듣기 시작할 수 있다.
final class ListeningPlayer: ObservableObject {
    enum ModelState: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    @Published private(set) var modelState: ModelState = .loading
    @Published private(set) var isSpeaking = false
    @Published private(set) var sentences: [String] = []
    @Published private(set) var currentSentence: Int?
    @Published private(set) var stats = ""

    private let synthesizer = KokoroSynthesizer.shared
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroSynthesizer.sampleRate, channels: 1)!
    private var playbackTask: Task<Void, Never>?
    /// 새로 재생하거나 멈출 때마다 올린다. 이전 요청에서 늦게 도착한 결과는 버린다.
    private var requestID = 0

    init() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }

    func prepare() async {
        guard modelState != .ready else { return }
        modelState = .loading
        do {
            let elapsed = try await synthesizer.load()
            modelState = .ready
            if elapsed > 0 {
                stats = String(format: "모델 준비 %.1f초", elapsed)
            }
        } catch {
            modelState = .unavailable(error.localizedDescription)
        }
    }

    func speak(_ text: String, voice: ListeningVoice, speed: Float) {
        play(Self.splitSentences(text), from: 0, voice: voice, speed: speed)
    }

    /// 지금 글의 한 문장부터 다시 읽는다.
    func replay(from index: Int, voice: ListeningVoice, speed: Float) {
        play(sentences, from: index, voice: voice, speed: speed)
    }

    func stop() {
        requestID += 1
        playbackTask?.cancel()
        playbackTask = nil
        playerNode.stop()
        isSpeaking = false
        currentSentence = nil
    }

    private func play(_ parts: [String], from start: Int, voice: ListeningVoice, speed: Float) {
        stop()
        sentences = parts
        guard modelState == .ready, parts.indices.contains(start) else { return }
        guard startAudio() else { return }

        let request = requestID
        isSpeaking = true
        let requestedAt = Date()

        playbackTask = Task { [weak self] in
            var generationTime = 0.0
            var audioTime = 0.0
            for index in start..<parts.count {
                guard let self, request == self.requestID, !Task.isCancelled else { return }
                let begin = Date()
                do {
                    let samples = try await self.synthesizer.generate(parts[index], voice: voice, speed: speed)
                    guard request == self.requestID else { return }
                    generationTime += Date().timeIntervalSince(begin)
                    audioTime += Double(samples.count) / KokoroSynthesizer.sampleRate

                    if index == start {
                        self.currentSentence = index
                        self.stats = String(format: "첫 문장까지 %.2f초", Date().timeIntervalSince(requestedAt))
                    }
                    let speedText = String(format: " · 실시간의 %.1f배", audioTime / max(generationTime, 0.001))
                    self.stats = (self.stats.components(separatedBy: " · ").first ?? "") + speedText

                    if let buffer = self.makeBuffer(samples) {
                        self.schedule(buffer, index: index, isLast: index == parts.count - 1, request: request)
                    }
                } catch {
                    self.stats = "\(index + 1)번째 문장을 만들지 못했어요: \(error.localizedDescription)"
                }
            }
        }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, index: Int, isLast: Bool, request: Int) {
        // 완료 콜백은 오디오 스레드에서 불리므로 메인 액터로 넘겨서 상태를 바꾼다.
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, request == self.requestID else { return }
                if isLast {
                    self.isSpeaking = false
                    self.currentSentence = nil
                } else {
                    self.currentSentence = index + 1
                }
            }
        }
    }

    private func startAudio() -> Bool {
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            #endif
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            playerNode.play()
            return true
        } catch {
            stats = "오디오를 시작하지 못했어요: \(error.localizedDescription)"
            return false
        }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                channel.update(from: base, count: source.count)
            }
        }
        return buffer
    }

    static func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
