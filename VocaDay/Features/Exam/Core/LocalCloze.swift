import Foundation

/// 사용자가 적은 예문에서 표제어(또는 활용형)를 찾아 빈칸 문제를 만든다.
/// AI 보강이 없어도 예문만 있으면 빈칸 고르기·빈칸 쓰기를 낼 수 있게 하는 로컬 규칙이다.
nonisolated enum LocalCloze {
    struct Result: Equatable, Sendable {
        /// 정답 자리를 `<>`로 바꾼 문장.
        var sentence: String
        /// 문장에 실제로 쓰인 표기 (예: postponed).
        var answer: String
        /// 활용 형태 분류. 빈칸 보기를 같은 형태끼리 고를 때 쓴다.
        var formClass: FormClass
        /// 빈칸을 만든 원래 예문.
        var example: String
    }

    /// 보기 호환성을 판단하는 거친 활용 분류.
    enum FormClass: String, Codable, Sendable {
        case base, s, ed, ing, er, est, other

        /// 보강 데이터의 `clozeForm`을 같은 분류로 옮긴다.
        init(enrichedForm: String) {
            switch enrichedForm {
            case "base": self = .base
            case "past", "past_participle": self = .ed
            case "present_participle": self = .ing
            case "third_person", "plural": self = .s
            case "comparative": self = .er
            case "superlative": self = .est
            default: self = .other
            }
        }
    }

    /// 예문 여러 줄("1. …\n2. …") 중 표제어가 들어 있는 첫 문장으로 빈칸을 만든다.
    /// - Parameter allowsComparative: 형용사일 때만 -er/-est 를 활용형으로 본다 (work → worker 오인 방지).
    static func build(term: String, example: String, allowsComparative: Bool = false) -> Result? {
        let head = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return nil }

        for line in exampleLines(example) {
            if let match = firstMatch(of: head, in: line, allowsComparative: allowsComparative) {
                let sentence = line.replacingCharacters(in: match.range, with: "<>")
                return Result(
                    sentence: sentence,
                    answer: String(line[match.range]),
                    formClass: match.formClass,
                    example: line
                )
            }
        }
        return nil
    }

    static func exampleLines(_ example: String) -> [String] {
        example
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: #"^\d+[.)]\s*"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    // MARK: 매칭

    private struct Match {
        var range: Range<String.Index>
        var formClass: FormClass
    }

    private static func firstMatch(of term: String, in line: String, allowsComparative: Bool) -> Match? {
        let parts = term.lowercased().split(separator: " ").map(String.init)
        guard let first = parts.first else { return nil }
        let tail = parts.dropFirst().map(NSRegularExpression.escapedPattern(for:))

        // 긴 활용형을 먼저 시도해야 "set"이 "settings" 일부에 걸리지 않는다 (단어 경계도 함께 검사).
        let variants = inflections(of: first)
            .filter { allowsComparative || ($0.formClass != .er && $0.formClass != .est) }
            .sorted { $0.form.count > $1.form.count }
        var best: Match?
        for variant in variants {
            let words = [NSRegularExpression.escapedPattern(for: variant.form)] + tail
            let pattern = #"(?i)(?<![A-Za-z'’-])"# + words.joined(separator: #"\s+"#) + #"(?![A-Za-z'’-])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let found = regex.firstMatch(in: line, range: range),
                  let swiftRange = Range(found.range, in: line) else { continue }
            if best == nil || swiftRange.lowerBound < best!.range.lowerBound {
                best = Match(range: swiftRange, formClass: variant.formClass)
            }
        }
        return best
    }

    struct Inflection: Hashable {
        var form: String
        var formClass: FormClass
    }

    /// 규칙 활용 + 자주 쓰는 불규칙 동사. 과하게 만들어도 단어 경계로 걸러지므로 안전하다.
    static func inflections(of word: String) -> [Inflection] {
        let w = word.lowercased()
        var result: [Inflection] = [Inflection(form: w, formClass: .base)]
        guard w.count >= 2, w.allSatisfy({ $0.isLetter }) else { return result }

        let vowels = Set("aeiou")
        let last = w.last!
        let beforeLast = w.dropLast().last
        let endsWithE = last == "e"
        let consonantY = last == "y" && !(beforeLast.map(vowels.contains) ?? false)
        // CVC 규칙 (stop → stopped). 마지막 자음이 w·x·y면 겹치지 않는다.
        let cvc = w.count >= 3
            && !vowels.contains(last) && !"wxy".contains(last)
            && (beforeLast.map(vowels.contains) ?? false)
            && !vowels.contains(w[w.index(w.endIndex, offsetBy: -3)])
        let doubled = w + String(last)

        // -s / -es
        if consonantY {
            result.append(Inflection(form: w.dropLast() + "ies", formClass: .s))
        } else if ["s", "x", "z"].contains(String(last)) || w.hasSuffix("ch") || w.hasSuffix("sh") || (last == "o" && !(beforeLast.map(vowels.contains) ?? true)) {
            result.append(Inflection(form: w + "es", formClass: .s))
        }
        result.append(Inflection(form: w + "s", formClass: .s))

        // -ed
        if endsWithE {
            result.append(Inflection(form: w + "d", formClass: .ed))
        } else if consonantY {
            result.append(Inflection(form: w.dropLast() + "ied", formClass: .ed))
        } else {
            result.append(Inflection(form: w + "ed", formClass: .ed))
            if cvc { result.append(Inflection(form: doubled + "ed", formClass: .ed)) }
        }

        // -ing
        if w.hasSuffix("ie") {
            result.append(Inflection(form: w.dropLast(2) + "ying", formClass: .ing))
        } else if endsWithE, !w.hasSuffix("ee") {
            result.append(Inflection(form: w.dropLast() + "ing", formClass: .ing))
        }
        result.append(Inflection(form: w + "ing", formClass: .ing))
        if cvc { result.append(Inflection(form: doubled + "ing", formClass: .ing)) }

        // -er / -est
        if consonantY {
            result.append(Inflection(form: w.dropLast() + "ier", formClass: .er))
            result.append(Inflection(form: w.dropLast() + "iest", formClass: .est))
        } else if endsWithE {
            result.append(Inflection(form: w + "r", formClass: .er))
            result.append(Inflection(form: w + "st", formClass: .est))
        } else {
            result.append(Inflection(form: w + "er", formClass: .er))
            result.append(Inflection(form: w + "est", formClass: .est))
        }

        if let irregular = irregularVerbs[w] {
            result.append(contentsOf: irregular.map { Inflection(form: $0, formClass: .ed) })
        }
        return Array(Set(result))
    }

    /// 자주 쓰는 불규칙 동사의 과거형·과거분사.
    private static let irregularVerbs: [String: [String]] = [
        "be": ["was", "were", "been"], "become": ["became"], "begin": ["began", "begun"],
        "break": ["broke", "broken"], "bring": ["brought"], "build": ["built"], "buy": ["bought"],
        "catch": ["caught"], "choose": ["chose", "chosen"], "come": ["came"], "cost": ["cost"],
        "cut": ["cut"], "deal": ["dealt"], "do": ["did", "done"], "draw": ["drew", "drawn"],
        "drink": ["drank", "drunk"], "drive": ["drove", "driven"], "eat": ["ate", "eaten"],
        "fall": ["fell", "fallen"], "feel": ["felt"], "fight": ["fought"], "find": ["found"],
        "fly": ["flew", "flown"], "forget": ["forgot", "forgotten"], "forgive": ["forgave", "forgiven"],
        "get": ["got", "gotten"], "give": ["gave", "given"], "go": ["went", "gone"], "grow": ["grew", "grown"],
        "have": ["had"], "hear": ["heard"], "hide": ["hid", "hidden"], "hold": ["held"], "keep": ["kept"],
        "know": ["knew", "known"], "lay": ["laid"], "lead": ["led"], "leave": ["left"], "lend": ["lent"],
        "let": ["let"], "lie": ["lay", "lain"], "lose": ["lost"], "make": ["made"], "mean": ["meant"],
        "meet": ["met"], "overcome": ["overcame"], "pay": ["paid"], "put": ["put"], "quit": ["quit"],
        "read": ["read"], "ride": ["rode", "ridden"], "rise": ["rose", "risen"], "run": ["ran"],
        "say": ["said"], "see": ["saw", "seen"], "seek": ["sought"], "sell": ["sold"], "send": ["sent"],
        "set": ["set"], "shake": ["shook", "shaken"], "shut": ["shut"], "sing": ["sang", "sung"],
        "sit": ["sat"], "sleep": ["slept"], "speak": ["spoke", "spoken"], "spend": ["spent"],
        "stand": ["stood"], "steal": ["stole", "stolen"], "strike": ["struck"], "swim": ["swam", "swum"],
        "take": ["took", "taken"], "teach": ["taught"], "tear": ["tore", "torn"], "tell": ["told"],
        "think": ["thought"], "throw": ["threw", "thrown"], "undergo": ["underwent", "undergone"],
        "understand": ["understood"], "undertake": ["undertook", "undertaken"], "wake": ["woke", "woken"],
        "wear": ["wore", "worn"], "win": ["won"], "withdraw": ["withdrew", "withdrawn"], "write": ["wrote", "written"],
        "arise": ["arose", "arisen"], "bear": ["bore", "borne"], "bind": ["bound"], "bid": ["bid"],
        "forecast": ["forecast"], "foresee": ["foresaw", "foreseen"], "oversee": ["oversaw", "overseen"],
        "spread": ["spread"], "upset": ["upset"], "wind": ["wound"], "withhold": ["withheld"],
    ]
}

// MARK: - 품사 힌트

extension ExamText {
    /// "v. 완성하다, n. 결말" 같은 사용자 뜻에서 품사 집합을 뽑는다 (보강 전 보기 호환성 판단용).
    static func partOfSpeechHints(_ meaning: String) -> Set<String> {
        let pattern = #"(?i)(?<![A-Za-z])(n|v|vt|vi|adj|adv|prep|conj|pron|phr)\."#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(meaning.startIndex..., in: meaning)
        var result: Set<String> = []
        for match in regex.matches(in: meaning, range: range) {
            guard let tokenRange = Range(match.range(at: 1), in: meaning) else { continue }
            switch meaning[tokenRange].lowercased() {
            case "n": result.insert("noun")
            case "v", "vt", "vi": result.insert("verb")
            case "adj": result.insert("adjective")
            case "adv": result.insert("adverb")
            case "prep": result.insert("preposition")
            case "conj": result.insert("conjunction")
            case "pron": result.insert("pronoun")
            case "phr": result.insert("phrasal_verb")
            default: break
            }
        }
        return result
    }
}
