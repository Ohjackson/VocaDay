import SwiftUI

struct WordInputCard: View {
    @Binding var inputWord: String
    var isInputFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("영단어 직접 입력", systemImage: "character.cursor.ibeam")
                .font(.headline)

            Text("한 번에 한 단어 또는 짧은 구문을 입력하세요. 임시 목록에 추가된 뒤 한국어 뜻을 직접 고칠 수 있습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("영단어 또는 구문 입력", text: $inputWord)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .submitLabel(.done)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()
                .focused(isInputFocused)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Label("임시 목록에 추가", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .calmCard()
        .onboardingSpotlight(.addInput)
    }
}
