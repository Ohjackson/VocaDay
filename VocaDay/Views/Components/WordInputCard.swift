import SwiftUI

struct WordInputCard: View {
    var title: String = "영단어 입력"
    @Binding var inputWord: String
    var isInputFocused: FocusState<Bool>.Binding
    var submitHint: String = "Enter로 추가"
    var isProcessing = false
    var primaryActionTitle: String?
    var secondaryActionTitle: String?
    var onPrimaryAction: (() -> Void)?
    var onSecondaryAction: (() -> Void)?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "character.cursor.ibeam")
                    .font(.headline)

                Spacer()

                Label(submitHint, systemImage: "return")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("영어 단어 하나 입력", text: $inputWord)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .submitLabel(.done)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()
                .focused(isInputFocused)
                .onSubmit(onSubmit)
                .disabled(isProcessing)

            if primaryActionTitle != nil || secondaryActionTitle != nil {
                HStack(spacing: 10) {
                    if let secondaryActionTitle, let onSecondaryAction {
                        Button(secondaryActionTitle, action: onSecondaryAction)
                            .buttonStyle(.bordered)
                            .disabled(isProcessing || inputWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Spacer(minLength: 0)

                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                        Text("생성 중…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else if let primaryActionTitle, let onPrimaryAction {
                        Button(primaryActionTitle, action: onPrimaryAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(inputWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .calmCard()
    }
}
