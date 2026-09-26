import Foundation
import NaturalLanguage

/// 기기 내장 영어 단어 임베딩(NLEmbedding). 빈칸 고르기 오답이 정답과 같은 주제인지 가늠하는 데만 쓴다.
/// 네트워크를 쓰지 않고, 임베딩을 못 불러오거나 사전에 없는 표현(구·숙어)이면 nil → 기존 규칙 그대로.
nonisolated enum WordEmbedding {
    nonisolated(unsafe) private static let english = NLEmbedding.wordEmbedding(for: .english)
    private static let lock = NSLock()

    /// 한 단어짜리 표제어의 단위 벡터. 구(공백 포함)나 사전에 없는 단어는 nil.
    static func unitVector(for term: String) -> [Double]? {
        let key = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        let raw = lock.withLock { english?.vector(for: key) }
        return raw.flatMap(normalized)
    }

    /// 코사인 거리 (1 − cos). 0에 가까울수록 비슷하다. NLEmbedding.distance(.cosine)와 같은 척도.
    static func cosineDistance(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot = 0.0
        for i in lhs.indices { dot += lhs[i] * rhs[i] }
        return 1 - dot
    }

    static func normalized(_ vector: [Double]) -> [Double]? {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard length > 0 else { return nil }
        return vector.map { $0 / length }
    }
}
