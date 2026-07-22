import SwiftUI

struct WordInputCard: View {
    @Binding var inputWord: String
    var isInputFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextField("Enter English word", text: $inputWord)
                .textFieldStyle(.roundedBorder)
                .font(.title2)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .focused(isInputFocused)
                .onSubmit(onSubmit)
                .frame(maxWidth: 520)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .calmCard()
        .onboardingSpotlight(.addInput)
    }
}
