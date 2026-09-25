import SwiftUI

struct DayDestinationOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
}

struct AddWordsSetupCard: View {
    let destinations: [DayDestinationOption]
    @Binding var selectedDestinationID: UUID?
    let showsEntryMode: Bool
    @Binding var entryMode: AddEntryMode
    let onCreateDestination: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            destinationPicker

            if showsEntryMode {
                Divider()
                entryModePicker
            }
        }
        .padding(16)
        .calmCard()
    }

    private var destinationPicker: some View {
        HStack(spacing: 14) {
            Label("저장 위치", systemImage: "calendar")
                .font(.headline)

            Spacer(minLength: 8)

            if destinations.isEmpty {
                Button(action: onCreateDestination) {
                    Label("첫 데이 만들기", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    Picker("저장할 데이", selection: $selectedDestinationID) {
                        ForEach(destinations) { destination in
                            Text(destination.title).tag(Optional(destination.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Button(action: onCreateDestination) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("새 데이 만들기")
                    .help("새 데이를 만들고 저장 위치로 선택")
                }
            }
        }
    }

    private var entryModePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("입력 방법", systemImage: "square.and.pencil")
                .font(.headline)

            Picker("입력 방법", selection: $entryMode) {
                ForEach(AddEntryMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct AddWordsGuideCard: View {
    let title: String
    let message: String
    let systemImage: String
    let showsHelpLink: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsHelpLink {
                    NavigationLink("JSON 사용법 보기", value: AppRoute.addWordsHelp)
                        .font(.caption.weight(.semibold))
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("단어 추가 방법 안내 숨기기")
            .help("안내 숨기기")
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.14))
        }
    }
}
