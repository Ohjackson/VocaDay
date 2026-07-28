import SwiftUI

struct ReviewCardView: View {
    let word: VocaWord
    let showingMeaning: Bool
    let onShowMeaning: () -> Void
    let onKnow: () -> Void
    let onAgain: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text(word.english)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    statusPill(WordStatus(rawValue: word.status)?.displayName ?? "새 단어")
                    if !word.note.isEmpty {
                        statusPill(word.note)
                    }
                    if !word.toeicTag.isEmpty {
                        statusPill(word.toeicTag)
                    }
                }
            }

            if showingMeaning {
                VStack(spacing: 12) {
                    Text(word.meaningKo.isEmpty ? "아직 한국어 뜻이 없습니다." : word.meaningKo)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)

                    if !word.exampleEn.isEmpty || !word.exampleKo.isEmpty {
                        VStack(spacing: 6) {
                            if !word.exampleEn.isEmpty {
                                Text(word.exampleEn)
                                    .font(.body)
                            }

                            if !word.exampleKo.isEmpty {
                                Text(word.exampleKo)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.center)
                    }
                }
            } else {
                Button {
                    onShowMeaning()
                } label: {
                    Label("뜻 보기", systemImage: "eye")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if showingMeaning {
                HStack(spacing: 12) {
                    Button {
                        onAgain()
                    } label: {
                        Label("다시", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        onKnow()
                    } label: {
                        Label("알아요", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            Divider()

            HStack {
                stat(title: "복습", value: word.reviewCount)
                stat(title: "정답", value: word.correctCount)
                stat(title: "오답", value: word.wrongCount)
                stat(title: "레벨", value: word.masteryLevel)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .calmCard()
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(Capsule())
    }

    private func stat(title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
