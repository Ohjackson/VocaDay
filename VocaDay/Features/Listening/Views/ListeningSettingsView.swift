import SwiftUI
import Translation

/// 리스닝 탭 톱니바퀴 화면. 책 읽기에 필요한 것들을 한곳에서 받고 확인한다.
/// - 기기 사전: 단어 카드의 사전 버튼이 여는 Apple 사전. 한국어-영어 사전을 받으면 영한 뜻이 나온다.
/// - 앱 사전: 앱에 들어 있는 위키낱말사전의 출처와 라이선스.
/// - 번역 언어 팩: 가져온 책 문장 번역(영→한, 기기 안).
/// - 음성 모델: Kokoro. 앱에 들어 있어서 받을 것은 없고, 불러오기와 시험만 한다.
struct ListeningSettingsView: View {
    @AppStorage(ReaderStorageKey.voiceID) private var voiceID = ListeningVoice.fallback.id
    @AppStorage(ReaderStorageKey.speed) private var speed = 1.0
    @AppStorage("listeningTestSentence") private var testSentence = Self.defaultTestSentence

    @State private var player = ListeningPlayer()
    @State private var translator = BookTranslationService.shared
    @State private var packConfiguration: TranslationSession.Configuration?
    @State private var hasEnglishDictionary: Bool?
    @State private var showsDictionary = false
    @Environment(\.openURL) private var openURL

    static let defaultTestSentence = "Mina arrived at the office twenty minutes early on Monday."
    /// 영어 사전이 있는지 볼 때 쓰는 흔한 단어.
    private static let probeWord = "arrive"

    private var voice: ListeningVoice { ListeningVoice.voice(id: voiceID) }

    var body: some View {
        Form {
            appDictionarySection
            dictionarySection
            translationSection
            voiceModelSection
            voiceTestSection
        }
        .formStyle(.grouped)
        .navigationTitle("사전·음성 설정")
        .task {
            checkDictionary()
            await translator.checkPack(source: "en")
            await player.prepare()
        }
        .translationTask(packConfiguration) { session in
            // 언어 팩이 없으면 시스템이 받기 안내를 띄운다.
            do { try await session.prepareTranslation() } catch {}
            await translator.checkPack(source: "en")
        }
        #if os(iOS)
        .sheet(isPresented: $showsDictionary, onDismiss: checkDictionary) {
            // 사전에 없는 말을 넣으면 「사전 관리」 링크가 나온다. 여기서 사전을 받는다.
            SystemDictionarySheet(term: "vocaday")
                .ignoresSafeArea()
                .environment(\.colorScheme, SystemDictionarySheet.deviceColorScheme)
                .preferredColorScheme(SystemDictionarySheet.deviceColorScheme)
        }
        #endif
        .onDisappear { player.stop() }
    }

    // MARK: - 앱 사전

    /// CC BY-SA 4.0 조건: 출처, 라이선스, 다듬었다는 사실을 밝힌다.
    private var appDictionarySection: some View {
        let dictionary = WiktionaryDictionary.shared
        return Section {
            HStack {
                Text("위키낱말사전 (영어 → 한국어)")
                Spacer()
                Text("\(dictionary.words.count.formatted())개")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Link(destination: WiktionaryDictionary.siteURL) {
                Label("한국어 위키낱말사전", systemImage: "books.vertical")
            }
            Link(destination: WiktionaryDictionary.licenseURL) {
                Label("라이선스 \(dictionary.license)", systemImage: "doc.text")
            }
        } header: {
            Text("앱 사전")
        } footer: {
            Text("앱에 들어 있어서 따로 받지 않아요. 한국어 위키낱말사전 기여자들이 쓴 글에서 영어 뜻과 예문만 골라 짧게 다듬었어요. (\(dictionary.dumpDate) 기준, kaikki.org 추출) 예문 가운데 일부는 앱 안의 문장이에요.")
        }
    }

    // MARK: - 사전

    private var dictionarySection: some View {
        Section {
            statusRow(
                "영어 사전",
                state: hasEnglishDictionary.map { $0 ? .ready : .missing },
                readyText: "있음",
                missingText: "없음"
            )
            #if os(iOS)
            Button {
                showsDictionary = true
            } label: {
                Label("사전 받기·관리", systemImage: "arrow.down.circle")
            }
            #else
            Button {
                if let url = SystemDictionary.url(for: Self.probeWord) { openURL(url) }
            } label: {
                Label("사전 앱 열기", systemImage: "character.book.closed")
            }
            Button("다시 확인", action: checkDictionary)
            #endif
        } header: {
            Text("기기 사전")
        } footer: {
            #if os(iOS)
            Text("「사전 받기·관리」에서 「사전 관리」를 누르고 한국어-영어 사전을 받으면 단어 카드에서 영한 뜻이 나와요.")
            #else
            Text("사전 앱 › 설정(⌘,)에서 한국어-영어 사전을 켜고 맨 위로 올리면 단어 카드에 영한 뜻이 나와요.")
            #endif
        }
    }

    private func checkDictionary() {
        hasEnglishDictionary = SystemDictionary.hasDefinition(for: Self.probeWord)
    }

    // MARK: - 번역 언어 팩

    private var translationSection: some View {
        Section {
            switch translator.packStatus["en"] ?? .unknown {
            case .unknown:
                statusRow("영어 → 한국어", state: nil, readyText: "", missingText: "")
            case .installed:
                statusRow("영어 → 한국어", state: .ready, readyText: "받음", missingText: "")
            case .needsDownload:
                statusRow("영어 → 한국어", state: .missing, readyText: "", missingText: "받아야 함")
                Button(action: requestPack) {
                    Label("번역 언어 팩 받기", systemImage: "arrow.down.circle")
                }
            case .unsupported:
                statusRow("영어 → 한국어", state: .missing, readyText: "", missingText: "지원 안 함")
            }
        } header: {
            Text("번역 언어 팩")
        } footer: {
            Text("PDF로 가져온 책의 문장과, 앱 사전에 없는 단어를 기기 안에서 한국어로 번역할 때 써요.")
        }
    }

    private func requestPack() {
        let configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: BookTranslationService.targetLanguage
        )
        if packConfiguration == configuration {
            packConfiguration?.invalidate()
        } else {
            packConfiguration = configuration
        }
    }

    // MARK: - 음성 모델

    private var voiceModelSection: some View {
        Section {
            switch player.modelState {
            case .loading:
                statusRow("Kokoro 음성 모델", state: nil, readyText: "", missingText: "")
            case .ready:
                statusRow("Kokoro 음성 모델", state: .ready, readyText: "준비됨", missingText: "")
            case .unavailable(let reason):
                statusRow("Kokoro 음성 모델", state: .missing, readyText: "", missingText: "쓸 수 없음")
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("다시 불러오기") { Task { await player.prepare() } }
            }
        } header: {
            Text("음성 모델")
        } footer: {
            Text("모델은 앱에 들어 있어서 따로 받지 않아요. 기기 안에서 음성을 만들어 인터넷이 필요 없어요.")
        }
    }

    // MARK: - 음성 시험

    private var voiceTestSection: some View {
        Section {
            TextField("시험 문장", text: $testSentence, axis: .vertical)
                .lineLimit(2...4)
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
            Button {
                if player.isSpeaking {
                    player.stop()
                } else {
                    player.speak(testSentence, voice: voice, speed: Float(speed))
                }
            } label: {
                Label(player.isSpeaking ? "정지" : "들어 보기", systemImage: player.isSpeaking ? "stop.fill" : "play.fill")
            }
            .disabled(player.modelState != .ready || testSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("음성 시험")
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text("여기서 고른 보이스와 속도는 책 읽기에도 그대로 쓰여요.")
                if !player.stats.isEmpty { Text(player.stats) }
            }
        }
    }

    // MARK: - 공통

    private enum RowState { case ready, missing }

    /// 이름 + 오른쪽 상태. `state` 가 nil 이면 확인 중.
    private func statusRow(_ title: String, state: RowState?, readyText: String, missingText: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            switch state {
            case nil:
                ProgressView().controlSize(.small)
            case .ready?:
                Label(readyText, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .missing?:
                Label(missingText, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}
