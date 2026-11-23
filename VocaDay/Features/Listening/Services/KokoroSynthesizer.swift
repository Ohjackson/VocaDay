import Foundation
import KokoroSwift
import MLX

/// Kokoro-82M으로 영어 문장을 음성 샘플로 만든다. 모델은 앱 전체에서 한 번만 불러온다.
///
/// MLX는 GPU(Metal)가 필요해서 iOS 시뮬레이터에서는 쓸 수 없다. 실기기와 Mac에서만 동작한다.
actor KokoroSynthesizer {
    static let shared = KokoroSynthesizer()

    nonisolated static let sampleRate = Double(KokoroTTS.Constants.samplingRate)

    enum Failure: LocalizedError {
        case unsupportedEnvironment
        case modelMissing
        case voiceMissing(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedEnvironment:
                return "시뮬레이터에서는 Kokoro를 실행할 수 없어요. 실기기나 Mac에서 확인해 주세요."
            case .modelMissing:
                return "음성 모델 파일이 없어요. scripts/fetch_kokoro_model.sh를 실행한 뒤 다시 빌드해 주세요."
            case .voiceMissing(let id):
                return "보이스 파일이 없어요: \(id)"
            }
        }
    }

    private static let cacheLimit = 64 * 1024 * 1024

    private var tts: KokoroTTS?
    private var styles: [String: MLXArray] = [:]

    /// 모델을 불러오고 한 번 미리 생성해 둔다. 첫 문장이 늦지 않게 하려는 것이다.
    /// 이미 불러왔으면 바로 0을 돌려준다.
    func load() throws -> TimeInterval {
        if tts != nil { return 0 }
        #if targetEnvironment(simulator)
        throw Failure.unsupportedEnvironment
        #else
        let start = Date()
        guard let url = Bundle.main.url(forResource: "kokoro-v1_0", withExtension: "safetensors") else {
            throw Failure.modelMissing
        }
        // MLX는 쓰고 난 GPU 버퍼를 기본으로 무한정 캐시한다. 문장을 계속 만들면 수 GB까지 커져
        // iPhone 메모리 한도(EXC_RESOURCE)에 걸려 앱이 죽었다. 캐시를 작게 묶는다.
        Memory.cacheLimit = Self.cacheLimit
        let engine = KokoroTTS(modelPath: url)
        tts = engine
        let warmUp = ListeningVoice.fallback
        _ = try engine.generateAudio(voice: try style(for: warmUp), language: language(for: warmUp), text: "Ready.")
        return Date().timeIntervalSince(start)
        #endif
    }

    func generate(_ text: String, voice: ListeningVoice, speed: Float) throws -> [Float] {
        if tts == nil { _ = try load() }
        guard let tts else { throw Failure.modelMissing }
        let (samples, _) = try tts.generateAudio(
            voice: try style(for: voice),
            language: language(for: voice),
            text: text,
            speed: speed
        )
        Memory.clearCache()
        return samples
    }

    private func style(for voice: ListeningVoice) throws -> MLXArray {
        if let cached = styles[voice.id] { return cached }
        guard let url = Bundle.main.url(forResource: "kokoro-voice-\(voice.id)", withExtension: "safetensors"),
              let style = try? MLX.loadArrays(url: url)["voice"]
        else { throw Failure.voiceMissing(voice.id) }
        styles[voice.id] = style
        return style
    }

    private func language(for voice: ListeningVoice) -> Language {
        voice.isBritish ? .enGB : .enUS
    }
}
