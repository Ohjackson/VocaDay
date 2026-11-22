import SwiftUI

/// 직접 넣은 글 듣기. 영어 글을 넣으면 Kokoro 보이스로 한 문장씩 읽어 준다. 기기 안에서만 음성을 만든다.
struct ListeningFreeTextView: View {
    @State private var player = ListeningPlayer()
    @AppStorage("listeningText") private var text = ListeningFreeTextView.sampleText
    @AppStorage("listeningVoiceID") private var voiceID = ListeningVoice.fallback.id
    @AppStorage("listeningSpeed") private var speed = 1.0

    static let sampleText = """
        The quarterly report shows that sales increased by twelve percent. \
        Management plans to expand the marketing budget next year. \
        All employees are invited to the annual meeting on Friday.
        """

    private var voice: ListeningVoice { ListeningVoice.voice(id: voiceID) }

    var body: some View {
        Form {
            Section("영어 글") {
                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
            }

            Section("보이스") {
                Picker("보이스", selection: $voiceID) {
                    ForEach(ListeningVoice.all) { voice in
                        Text("\(voice.name) · \(voice.accent)").tag(voice.id)
                    }
                }
                HStack {
                    Text("속도")
                    Slider(value: $speed, in: 0.6...1.4, step: 0.1)
                    Text(String(format: "%.1f×", speed))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    if player.isSpeaking {
                        player.stop()
                    } else {
                        player.speak(text, voice: voice, speed: Float(speed))
                    }
                } label: {
                    Label(player.isSpeaking ? "정지" : "읽기", systemImage: player.isSpeaking ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(player.modelState != .ready || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                    if !player.stats.isEmpty {
                        Text(player.stats)
                    }
                }
            }

            if !player.sentences.isEmpty {
                Section("문장 (눌러서 다시 듣기)") {
                    ForEach(Array(player.sentences.enumerated()), id: \.offset) { index, sentence in
                        Button {
                            player.replay(from: index, voice: voice, speed: Float(speed))
                        } label: {
                            Text(sentence)
                                .foregroundStyle(player.currentSentence == index ? Color.accentColor : .primary)
                                .fontWeight(player.currentSentence == index ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(player.modelState != .ready)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("직접 넣은 글 듣기")
        .task { await player.prepare() }
        .onDisappear { player.stop() }
    }

    private var statusText: String {
        switch player.modelState {
        case .loading: return "음성 모델을 불러오는 중…"
        case .ready: return "기기 안에서 음성을 만들어요. 인터넷이 필요 없어요."
        case .unavailable(let reason): return reason
        }
    }
}
