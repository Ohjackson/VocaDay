import SwiftUI

struct ExamSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ExamSettingsKeys.allowsTypo) private var allowsTypo = true
    @AppStorage(ExamSettingsKeys.allowsNearMissRetry) private var allowsNearMissRetry = true
    @AppStorage(ExamSettingsKeys.showsExampleTranslation) private var showsExampleTranslation = false
    @AppStorage(ExamSettingsKeys.introducesNewWords) private var introducesNewWords = false

    @State private var apiKeyInput = ""
    @State private var hasAPIKey = GeminiAPIKeyStore.standard.hasAPIKey
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if hasAPIKey {
                    LabeledContent("Gemini API 키", value: "저장됨")
                    Button("키 삭제", role: .destructive) {
                        do {
                            try GeminiAPIKeyStore.standard.delete()
                            hasAPIKey = false
                            message = "키를 삭제했어요."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                } else {
                    SecureField("Gemini API 키", text: $apiKeyInput)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button("저장") {
                        do {
                            try GeminiAPIKeyStore.standard.save(apiKeyInput)
                            apiKeyInput = ""
                            hasAPIKey = true
                            message = "키를 이 기기의 키체인에 저장했어요."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("문제 준비 (Gemini)")
            } footer: {
                Text("키를 넣으면 시험 문제를 만들기 위해 단어, 뜻, 예문을 Google Gemini API(\(GeminiClient.defaultModelID))로 보냅니다. 키는 iCloud로 동기화되지 않고 이 기기에만 저장됩니다. 키가 없어도 예문에 단어가 들어 있으면 모든 문제 유형을 풀 수 있어요. 키를 넣으면 품사·활용형을 분석해 보기를 더 정교하게 만들어요.")
            }

            Section {
                Toggle("한 글자 오타는 정답으로 인정", isOn: $allowsTypo)
                Toggle("다른 형태·비슷한 단어는 한 번 더 기회", isOn: $allowsNearMissRetry)
                Toggle("빈칸 문제의 예문 해석 처음부터 보기", isOn: $showsExampleTranslation)
                Toggle("처음 보는 단어는 먼저 뜻 보여 주기", isOn: $introducesNewWords)
            } header: {
                Text("채점")
            } footer: {
                Text("하루 최대 \(SRSEngine.dailyReviewLimit)개, 틀린 단어는 \(SRSEngine.retryDelayHours)시간 뒤 재도전해요. 빈칸 문제에서 해석을 열어 본 문제는 세션 끝에 해석 없이 한 번 더 나와요.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("시험 설정")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("완료") { dismiss() }
            }
        }
    }
}
