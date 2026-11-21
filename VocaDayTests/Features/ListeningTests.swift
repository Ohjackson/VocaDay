import XCTest
@testable import VocaDay

final class ListeningTests: XCTestCase {
    func testSplitsTextIntoTrimmedSentences() {
        let sentences = ListeningPlayer.splitSentences("  Sales rose by 12%. The meeting is on Friday!\nSee you there.  ")
        XCTAssertEqual(sentences, ["Sales rose by 12%.", "The meeting is on Friday!", "See you there."])
    }

    func testEveryVoiceHasABundledFileName() {
        XCTAssertEqual(ListeningVoice.all.count, 5)
        XCTAssertEqual(ListeningVoice.voice(id: "unknown"), ListeningVoice.fallback)
        XCTAssertTrue(ListeningVoice.voice(id: "bf_emma").isBritish)
        XCTAssertFalse(ListeningVoice.voice(id: "am_michael").isBritish)
    }

    /// 실제 모델로 문장 하나를 만든다. 모델 파일이 없는 환경(새로 받은 저장소)과 시뮬레이터에서는 건너뛴다.
    func testGeneratesSpeechForAmericanAndBritishVoices() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX는 시뮬레이터에서 동작하지 않는다.")
        #else
        guard Bundle.main.url(forResource: "kokoro-v1_0", withExtension: "safetensors") != nil else {
            throw XCTSkip("Kokoro 모델 파일이 없다. scripts/fetch_kokoro_model.sh 참고.")
        }
        let synthesizer = KokoroSynthesizer.shared
        for id in ["af_heart", "bm_george"] {
            let samples = try await synthesizer.generate(
                "The quarterly report shows that sales increased.",
                voice: ListeningVoice.voice(id: id),
                speed: 1.0
            )
            let seconds = Double(samples.count) / KokoroSynthesizer.sampleRate
            XCTAssertGreaterThan(seconds, 1.0, id)
            XCTAssertLessThan(seconds, 8.0, id)
            XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.01, "\(id) is silent")
        }
        #endif
    }
}
