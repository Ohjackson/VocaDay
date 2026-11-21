import Foundation

/// 리스닝에서 고를 수 있는 Kokoro 보이스 다섯 개.
/// `id`는 번들 파일 이름 `kokoro-voice-<id>.safetensors`와 같다.
nonisolated struct ListeningVoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let accent: String

    /// "b"로 시작하는 보이스는 영국식, 나머지는 미국식으로 발음한다.
    var isBritish: Bool { id.hasPrefix("b") }

    static let all: [ListeningVoice] = [
        ListeningVoice(id: "af_heart", name: "Heart", accent: "미국 · 여성"),
        ListeningVoice(id: "af_bella", name: "Bella", accent: "미국 · 여성"),
        ListeningVoice(id: "am_michael", name: "Michael", accent: "미국 · 남성"),
        ListeningVoice(id: "bf_emma", name: "Emma", accent: "영국 · 여성"),
        ListeningVoice(id: "bm_george", name: "George", accent: "영국 · 남성"),
    ]

    static var fallback: ListeningVoice { all[0] }

    static func voice(id: String) -> ListeningVoice {
        all.first { $0.id == id } ?? fallback
    }
}
