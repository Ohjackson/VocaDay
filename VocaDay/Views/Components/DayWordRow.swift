import SwiftUI

/// 데이 단어장의 한 줄. 줄을 누르면 `onTap` (읽기 모드: 펼치기, 듣기 모드: 발음).
/// 펼치면 예문·번역·메모와 편집/발음/삭제 버튼이 보인다.
struct DayWordRow: View {
    let number: Int
    let word: VocaWord
    let isExpanded: Bool
    let isSpeaking: Bool
    /// 줄을 누르면 발음하는 모드 (듣기). 오른쪽 표시를 펼침 화살표 대신 스피커로 바꾼다.
    var tapSpeaks = false
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSpeak: () -> Void
    let onDelete: () -> Void

    private var issues: [WordDataCheck.Issue] {
        WordDataCheck.issues(english: word.english, meaningKo: word.meaningKo, exampleEn: word.exampleEn, exampleKo: word.exampleKo)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)

            if isExpanded {
                details
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isSpeaking ? Color.accentColor.opacity(0.12) : (isExpanded ? AppTheme.raisedBackground : Color.clear))
        .contextMenu {
            Button("편집", systemImage: "pencil", action: onEdit)
            Button("발음 듣기", systemImage: "speaker.wave.2", action: onSpeak)
            Button("삭제", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    // MARK: 요약 줄

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 26, alignment: .trailing)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    english.frame(width: 220, alignment: .leading)
                    meaning
                    Spacer(minLength: 8)
                    badges
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        english
                        Spacer(minLength: 8)
                        badges
                    }
                    meaning
                }
            }

            Image(systemName: tapSpeaks ? "speaker.wave.2" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .opacity(isSpeaking ? 0 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var english: some View {
        HStack(spacing: 6) {
            Text(word.english)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if isSpeaking {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative)
            }
        }
    }

    private var meaning: some View {
        Text(word.meaningKo.isEmpty ? "뜻 없음" : word.meaningKo)
            .font(.subheadline)
            .foregroundStyle(word.meaningKo.isEmpty ? .tertiary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if let issueTitle {
                badge(issueTitle, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
            if word.wrongCount > 0 {
                badge("틀림 \(word.wrongCount)", systemImage: nil, tint: .secondary)
            }
        }
        .fixedSize()
    }

    /// 문제를 못 만드는 이유 중 가장 급한 것.
    private var issueTitle: String? {
        if issues.contains(.missingMeaning) { return "뜻 필요" }
        if issues.contains(.missingExample) { return "예문 필요" }
        if issues.contains(.exampleMissingWord) { return "예문에 단어 없음" }
        return nil
    }

    private func badge(_ title: String, systemImage: String?, tint: Color) -> some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: 펼친 내용

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            let examples = ExamText.examplePairs(en: word.exampleEn, ko: word.exampleKo)
            if examples.isEmpty {
                Text("예문이 없어요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 3) {
                        if !example.en.isEmpty {
                            Text(example.en)
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !example.ko.isEmpty {
                            Text(example.ko)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !word.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(word.note, systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !WordDataCheck.isQuizReady(issues) {
                WordDataCheckView(issues: issues, compact: true)
            }

            HStack(spacing: 8) {
                Button("편집", systemImage: "pencil", action: onEdit)
                Button("발음", systemImage: "speaker.wave.2", action: onSpeak)
                Spacer()
                Button("삭제", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.leading, 54)
        .padding(.trailing, 16)
        .padding(.bottom, 14)
    }
}
