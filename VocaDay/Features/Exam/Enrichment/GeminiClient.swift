import Foundation
import Security

enum GeminiAPIKeyStoreError: LocalizedError {
    case encodingFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "API 키를 저장할 수 있는 형식으로 변환하지 못했습니다."
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "오류 코드 \(status)"
            return "API 키 보안 저장소 오류: \(message)"
        }
    }
}

/// 사용자가 입력한 Gemini API 키를 Keychain에 보관한다 (단고초 GeminiAPIKeyStore와 같은 방식, 이 기기에만 저장).
nonisolated struct GeminiAPIKeyStore: Sendable {
    static let standard = GeminiAPIKeyStore()

    private let service = (Bundle.main.bundleIdentifier ?? "VocaDay") + ".gemini"
    private let account = "personal-api-key"

    var apiKey: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasAPIKey: Bool { apiKey != nil }

    func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else {
            throw GeminiAPIKeyStoreError.encodingFailed
        }

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw GeminiAPIKeyStoreError.keychain(updateStatus)
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GeminiAPIKeyStoreError.keychain(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GeminiAPIKeyStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

nonisolated enum GeminiError: LocalizedError, Equatable {
    case missingAPIKey
    case http(status: Int, message: String)
    case blocked(String)
    case emptyResponse(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Gemini API 키가 없습니다. 시험 설정에서 키를 입력하세요."
        case .http(let status, let message):
            status == 503
                ? "Gemini 서버에 요청이 몰려 지금은 보강할 수 없습니다. 잠시 뒤 다시 시도하세요."
                : "Gemini API 오류(\(status)): \(message)"
        case .blocked(let reason):
            "Gemini가 요청을 차단했습니다: \(reason)"
        case .emptyResponse(let detail):
            "Gemini 응답에 생성된 내용이 없습니다\(detail)."
        case .invalidJSON:
            "AI 응답을 단어 데이터로 읽지 못했습니다."
        }
    }

    /// 다시 요청해 볼 만한 오류인지 (검증 실패처럼 교정 재요청 대상).
    var isRecoverableByCorrection: Bool {
        self == .invalidJSON
    }
}

/// Gemini generateContent + 구조화 출력(responseSchema).
nonisolated struct GeminiClient: Sendable {
    /// 저가형 기본 모델 (단고초 기본값과 같음).
    static let defaultModelID = "gemini-3.5-flash-lite"

    var apiKey: String
    var modelID: String = GeminiClient.defaultModelID
    var thinkingLevel: String = "low"
    var session: URLSession = .shared

    func generateJSON(
        system: String,
        prompt: String,
        schema: [String: Any],
        maxOutputTokens: Int,
        timeout: TimeInterval = 60
    ) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent") else {
            throw GeminiError.http(status: -1, message: "잘못된 모델 주소")
        }

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
                "thinkingConfig": ["thinkingLevel": thinkingLevel],
                "maxOutputTokens": maxOutputTokens,
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        return try Self.extractText(from: data, response: response)
    }

    static func extractText(from data: Data, response: URLResponse) throws -> String {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200..<300).contains(status) else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw GeminiError.http(status: status, message: message)
        }
        if let feedback = json?["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
            throw GeminiError.blocked(reason)
        }
        let candidate = (json?["candidates"] as? [[String: Any]])?.first
        guard let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] else {
            let finish = (candidate?["finishReason"] as? String).map { ": \($0)" } ?? ""
            throw GeminiError.emptyResponse(finish)
        }
        // thinking 요약(thought: true)은 제외한다.
        let text = parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.emptyResponse("")
        }
        return text
    }
}
