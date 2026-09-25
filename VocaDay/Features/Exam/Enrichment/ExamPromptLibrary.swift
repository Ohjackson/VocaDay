import Foundation

enum ExamPromptError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "번들에서 프롬프트 파일(\(name))을 찾을 수 없습니다."
        }
    }
}

/// docs/srs-port/prompts 를 번들 리소스(Resources/ExamPrompts)로 넣고 ${...} 치환으로 쓴다.
nonisolated struct ExamPromptLibrary: Sendable {
    let system: String
    let wordPrompt: String
    let backfillPrompt: String
    /// en_word_schema.json 원문. Gemini responseSchema로 그대로 보낸다.
    let wordSchemaJSON: String

    static func load(from bundle: Bundle = .main) throws -> ExamPromptLibrary {
        ExamPromptLibrary(
            system: try resource("en_word_system", "txt", bundle),
            wordPrompt: try resource("en_words_prompt", "txt", bundle),
            backfillPrompt: try resource("en_backfill_prompt", "txt", bundle),
            wordSchemaJSON: try resource("en_word_schema", "json", bundle)
        )
    }

    /// ${key} 를 값으로 바꾼다. 값 안의 ${...} 가 다시 치환되지 않도록 한 번에 처리한다.
    static func substitute(_ template: String, _ values: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\$\{([a-z_]+)\}"#) else { return template }
        var result = ""
        var cursor = template.startIndex
        let range = NSRange(template.startIndex..., in: template)
        for match in regex.matches(in: template, range: range) {
            guard let whole = Range(match.range, in: template),
                  let keyRange = Range(match.range(at: 1), in: template) else { continue }
            result += template[cursor..<whole.lowerBound]
            let key = String(template[keyRange])
            result += values[key] ?? String(template[whole])
            cursor = whole.upperBound
        }
        result += template[cursor...]
        return result
    }

    /// 사용자 입력은 XML 태그 경계를 깨지 않게 꺾쇠를 이스케이프한다.
    static func escapeForTag(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<", with: "‹")
            .replacingOccurrences(of: ">", with: "›")
    }

    func singleWordPrompt(for input: EnrichmentInput) -> String {
        Self.substitute(wordPrompt, [
            "term": Self.escapeForTag(input.term),
            "user_meaning_ko": Self.escapeForTag(input.userMeaningKo),
            "user_example": Self.escapeForTag(input.userExample),
        ])
    }

    /// en_words_prompt.txt 의 <rules>…</rules> 와 <examples>…</examples> 블록.
    var entryRules: String {
        [Self.block("rules", in: wordPrompt), Self.block("examples", in: wordPrompt)]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    func batchPrompt(for inputs: [EnrichmentInput]) -> String {
        let items: [[String: String]] = inputs.map {
            ["id": $0.id.uuidString, "term": $0.term, "user_meaning_ko": $0.userMeaningKo, "user_example": $0.userExample]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let itemsJSON = (try? encoder.encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        // 주석(<!-- -->)은 사람용 안내라 모델에는 보내지 않는다.
        let template = backfillPrompt.replacingOccurrences(
            of: #"<!--[\s\S]*?-->\n?"#,
            with: "",
            options: .regularExpression
        )
        return Self.substitute(template, [
            "items_json": Self.escapeForTag(itemsJSON),
            "entry_rules": entryRules,
        ])
    }

    func wordSchema() throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(wordSchemaJSON.utf8)) as? [String: Any] else {
            throw ExamPromptError.missingResource("en_word_schema.json")
        }
        return object
    }

    /// 일괄 보강용: 각 항목에 id를 붙인 배열 스키마.
    func batchSchema() throws -> [String: Any] {
        var item = try wordSchema()
        var properties = item["properties"] as? [String: Any] ?? [:]
        properties["id"] = ["type": "STRING"]
        item["properties"] = properties
        item["required"] = ["id"] + (item["required"] as? [String] ?? [])
        item["propertyOrdering"] = ["id"] + (item["propertyOrdering"] as? [String] ?? [])
        return ["type": "ARRAY", "items": item]
    }

    static func withCorrection(_ prompt: String, _ message: String) -> String {
        """
        \(prompt)

        <correction>
        The previous response failed these checks:
        \(message)
        Re-check every rule and return only the corrected JSON.
        </correction>
        """
    }

    private static func block(_ tag: String, in text: String) -> String? {
        guard let start = text.range(of: "<\(tag)>"),
              let end = text.range(of: "</\(tag)>", range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.lowerBound..<end.upperBound])
    }

    private static func resource(_ name: String, _ ext: String, _ bundle: Bundle) throws -> String {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ExamPromptError.missingResource("\(name).\(ext)")
        }
        return text
    }
}

/// 보강 요청 한 건. 사용자 데이터를 기준으로 삼는다 (SPEC §6.1).
nonisolated struct EnrichmentInput: Equatable, Sendable {
    var id: UUID
    var term: String
    var userMeaningKo: String
    var userExample: String
    /// 요청 당시 단어 지문. 응답을 저장할 때 사용자가 그새 단어를 고쳤는지 확인한다.
    var fingerprint: String
}
