import SwiftUI

struct AppActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var isProminent = false
    var isDisabled = false
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if isProminent {
            actionButton
                .buttonStyle(.borderedProminent)
        } else {
            actionButton
                .buttonStyle(.bordered)
        }
    }

    private var actionButton: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .disabled(isDisabled)
        .accessibilityLabel(Text(title))
    }
}

struct AppToolbarActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
    }
}
