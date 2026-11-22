import AVFoundation
import Foundation
import Observation

/// 문장 목록을 Kokoro로 한 문장씩 만들어 이어서 재생한다.
///
/// 지금 문장이 나오는 동안 다음 문장을 미리 만들어 두어(`lookahead`) 문장 사이가 끊기지 않게 하고,
/// 긴 책이라도 남은 문장을 한꺼번에 만들지는 않는다.
@Observable
final class SentenceSpeaker {
    enum ModelState: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    /// 재생 대기열에 미리 넣어 둘 문장 수 (지금 나오는 문장 포함).
    static let lookahead = 2

    private(set) var modelState: ModelState = .loading
    private(set) var isSpeaking = false
    /// 지금 소리가 나는(또는 곧 나올) 문장 번호.
    private(set) var currentIndex: Int?
    private(set) var stats = ""

    /// 읽는 문장이 바뀔 때. 끝까지 읽으면 nil.
    @ObservationIgnored var onSentenceChange: ((Int?) -> Void)?

    @ObservationIgnored private let synthesizer = KokoroSynthesizer.shared
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroSynthesizer.sampleRate, channels: 1)!
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    /// 새로 재생하거나 멈출 때마다 올린다. 이전 요청에서 늦게 도착한 결과는 버린다.
    @ObservationIgnored private var requestID = 0
    /// 대기열에 들어가 아직 다 나오지 않은 문장 번호. 앞이 지금 나오는 문장이다.
    @ObservationIgnored private var scheduled: [Int] = []
    @ObservationIgnored private var generationFinished = false

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

    func play(_ sentences: [String], from start: Int, voice: ListeningVoice, speed: Float) {
        stop()
        guard modelState == .ready, sentences.indices.contains(start) else { return }
        guard startAudio() else { return }

        let request = requestID
        isSpeaking = true
        currentIndex = start
        generationFinished = false
        let requestedAt = Date()

        playbackTask = Task { [weak self] in
            var generationTime = 0.0
            var audioTime = 0.0
            for index in start..<sentences.count {
                // 대기열이 차 있으면 앞 문장이 끝날 때까지 기다린다.
                while let self, request == self.requestID, self.scheduled.count >= Self.lookahead {
                    try? await Task.sleep(for: .milliseconds(60))
                }
                guard let self, request == self.requestID, !Task.isCancelled else { return }
                let begin = Date()
                do {
                    let samples = try await self.synthesizer.generate(sentences[index], voice: voice, speed: speed)
                    guard request == self.requestID else { return }
                    generationTime += Date().timeIntervalSince(begin)
                    audioTime += Double(samples.count) / KokoroSynthesizer.sampleRate
                    if index == start {
                        self.stats = String(format: "첫 문장까지 %.2f초", Date().timeIntervalSince(requestedAt))
                        self.onSentenceChange?(start)
                    }
                    let speedText = String(format: " · 실시간의 %.1f배", audioTime / max(generationTime, 0.001))
                    self.stats = (self.stats.components(separatedBy: " · ").first ?? "") + speedText
                    if let buffer = self.makeBuffer(samples) {
                        self.schedule(buffer, index: index, request: request)
                    }
                } catch {
                    self.stats = "\(index + 1)번째 문장을 만들지 못했어요: \(error.localizedDescription)"
                }
            }
            guard let self, request == self.requestID else { return }
            self.generationFinished = true
            if self.scheduled.isEmpty { self.finish() }
        }
    }

    func stop() {
        requestID += 1
        playbackTask?.cancel()
        playbackTask = nil
        playerNode.stop()
        scheduled = []
        generationFinished = false
        isSpeaking = false
        currentIndex = nil
    }

    private func finish() {
        isSpeaking = false
        currentIndex = nil
        onSentenceChange?(nil)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, index: Int, request: Int) {
        scheduled.append(index)
        // 완료 콜백은 오디오 스레드에서 불리므로 메인 액터로 넘겨서 상태를 바꾼다.
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.didPlay(index, request: request)
            }
        }
    }

    private func didPlay(_ index: Int, request: Int) {
        guard request == requestID else { return }
        scheduled.removeAll { $0 == index }
        if let next = scheduled.first {
            currentIndex = next
            onSentenceChange?(next)
        } else if generationFinished {
            finish()
        } else {
            // 다음 문장을 아직 만드는 중이다. 표시는 먼저 옮긴다.
            currentIndex = index + 1
            onSentenceChange?(index + 1)
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
}
