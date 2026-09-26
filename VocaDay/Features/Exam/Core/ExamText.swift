import Foundation

/// 시험보기에서 쓰는 문자열 정규화. docs/srs-port/samples/validate_reference.py 의 norm/words 와 같은 동작.
nonisolated enum ExamText {
    /// trim → 소문자 → ’ ‘ ʼ 를 ' 로 → 연속 공백 1칸 → 끝의 . , ! ? 제거 (SPEC §4.6)
    static func normalize(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for apostrophe in ["’", "‘", "ʼ"] {
            value = value.replacingOccurrences(of: apostrophe, with: "'")
        }
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[.,!?]+$"#, with: "", options: .regularExpression)
        return value
    }

    /// 소문자로 바꾼 뒤 [a-z'-]+ 토큰만 뽑는다.
    static func words(_ text: String) -> [String] {
        let lowered = text.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"[a-z'-]+"#) else { return [] }
        let range = NSRange(lowered.startIndex..., in: lowered)
        return regex.matches(in: lowered, range: range).compactMap { match in
            Range(match.range, in: lowered).map { String(lowered[$0]) }
        }
    }

    /// 토큰 배열 안에 phrase 토큰열이 몇 번 나오는지.
    static func phraseCount(in textWords: [String], phrase: String) -> Int {
        let target = words(phrase)
        guard !target.isEmpty, textWords.count >= target.count else { return 0 }
        var count = 0
        for start in 0...(textWords.count - target.count)
        where Array(textWords[start..<(start + target.count)]) == target {
            count += 1
        }
        return count
    }

    static func containsHangulSyllable(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    }

    /// 짝 맞추기 모호성 비교용 한국어 뜻 정규화 (SPEC §4 M1).
    /// 괄호 내용 제거 → 공백·문장부호 제거 → 끝의 하다/한/히/게 제거.
    static func normalizeMeaning(_ meaning: String) -> String {
        var value = meaning.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: "", options: .regularExpression)
        value = value.unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0) }
            .map(String.init)
            .joined()
        for suffix in ["하다", "한", "히", "게"] where value.hasSuffix(suffix) && value.count > suffix.count {
            value = String(value.dropLast(suffix.count))
            break
        }
        return value
    }

    /// 쉼표·세미콜론·슬래시로 나열된 뜻을 각각 정규화한 집합. 보강 전 사용자 뜻("결과, 성과")의 겹침 판정에 쓴다.
    static func meaningKeys(_ meaning: String) -> Set<String> {
        let parts = meaning.components(separatedBy: CharacterSet(charactersIn: ",;/·\n"))
        return Set(parts.map(normalizeMeaning).filter { !$0.isEmpty })
    }

    /// 기존 단어장의 "n. 대부분, 대량; adj. 대량의" 같은 뜻에서 품사 약어를 뗀다.
    static func strippingPartOfSpeechMarkers(_ meaning: String) -> String {
        let pattern = #"(?i)(?<![A-Za-z])(n|v|vt|vi|adj|adv|phr|prep|conj|pron|interj|int|idiom|aux)\.\s*"#
        return meaning
            .replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 영어 예문과 번역을 줄 번호끼리 짝짓는다 ("1. …\n2. …" 형식, 번호는 뗀다). 줄 수가 다르면 빈 칸으로 채운다.
    static func examplePairs(en: String, ko: String) -> [(en: String, ko: String)] {
        let english = LocalCloze.exampleLines(en)
        let korean = LocalCloze.exampleLines(ko)
        return (0..<max(english.count, korean.count)).map { index in
            (en: english.indices.contains(index) ? english[index] : "",
             ko: korean.indices.contains(index) ? korean[index] : "")
        }
    }

    /// "1. 첫 문장\n2. 둘째 문장" 형식이면 첫 문장만.
    static func firstExampleLine(_ example: String) -> String {
        let line = example
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.replacingOccurrences(of: #"^\d+[.)]\s*"#, with: "", options: .regularExpression)
    }

    /// 대체 유형·보기 선택을 위한 결정적 해시 (FNV-1a 64). Swift의 hashValue는 실행마다 바뀌므로 쓰지 않는다.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var previous = Array(0...right.count)
        for (i, leftCharacter) in left.enumerated() {
            var current = [i + 1]
            current.reserveCapacity(right.count + 1)
            for (j, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[j] + 1,
                    previous[j + 1] + 1,
                    previous[j] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[right.count]
    }
}

/// 결정적 난수 (SplitMix64). 같은 seed면 앱을 다시 켜도 같은 문제가 나온다.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    init(_ parts: String...) {
        state = ExamText.stableHash(parts.joined(separator: "|"))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
