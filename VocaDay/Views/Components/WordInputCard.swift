import SwiftUI

struct WordInputCard: View {
    var title: String = "영단어 입력"
    @Binding var inputWord: String
    var isInputFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "character.cursor.ibeam")
                    .font(.headline)

                Spacer()

                Label("Enter로 추가", systemImage: "return")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .calmCard()
    }
}
