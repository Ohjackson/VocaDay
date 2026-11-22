import SwiftUI

/// 오른쪽 위 버튼. 평소에는 이것만 보인다. 누르면 위·아래 막대를 보이고, 다시 누르면 숨긴다.
struct ReaderChromeToggle: View {
    @Binding var isShown: Bool
    let appearance: ReaderAppearance

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isShown.toggle() }
        } label: {
            Image(systemName: isShown ? "xmark" : "line.3.horizontal")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isShown ? appearance.accent : appearance.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isShown ? "메뉴 숨기기" : "메뉴 보기")
    }
}

/// 「⋯」 메뉴에서 여는 것들.
struct ReaderMenuActions {
    var showContents: () -> Void
    var showAppearance: () -> Void
}

/// 위 막대: 뒤로, 제목·저자, 「⋯」 메뉴. 테마의 책상 색 평면 + 1pt 경계선.
struct ReaderTopBar: View {
    let session: ReaderSession
    let appearance: ReaderAppearance
    let settings: ReaderSettingsBindings
    var safeTop: CGFloat = 0
    let actions: ReaderMenuActions
    @Binding var showsAppearance: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(appearance.accent)
            .accessibilityLabel("뒤로")

            VStack(alignment: .leading, spacing: 1) {
                Text(session.book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appearance.text)
                if let author = session.book.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(appearance.secondary)
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            ReaderMoreMenu(session: session, appearance: appearance, settings: settings, actions: actions)
                .background {
                    // 메뉴 단추 자체에 붙이면 메뉴가 닫히는 중에 위치를 잃는다. 같은 자리의 빈 뷰에 붙인다.
                    Color.clear
                        .popover(isPresented: $showsAppearance, arrowEdge: .top) {
                            ReaderAppearanceControls(
                                fontSize: settings.$fontSize,
                                lineHeight: settings.$lineHeight,
                                theme: settings.$theme,
                                followsSystemDark: settings.$followsSystemDark
                            )
                            .tint(appearance.accent)
                            .presentationCompactAdaptation(.popover)
                        }
                }

            // 오른쪽 끝은 막대 숨기기 버튼 자리 (`ReaderChromeToggle` 이 위에 겹친다).
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.top, safeTop)
        .padding(.bottom, 4)
        .background(appearance.desk)
        .overlay(alignment: .bottom) {
            Rectangle().fill(appearance.border).frame(height: 1)
        }
    }
}

/// 「⋯」 메뉴: 이 위치 북마크, 목차·북마크 목록, 보기 설정, 목소리·속도.
struct ReaderMoreMenu: View {
    static let speeds: [Double] = [0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3]

    let session: ReaderSession
    let appearance: ReaderAppearance
    let settings: ReaderSettingsBindings
    let actions: ReaderMenuActions

    var body: some View {
        let isBookmarked = session.bookmark(at: session.position) != nil
        Menu {
            Button(isBookmarked ? "이 위치 북마크 삭제" : "이 위치 북마크", systemImage: isBookmarked ? "bookmark.slash" : "bookmark") {
                session.toggleBookmark(at: session.position)
            }
            Button("목차·북마크", systemImage: "list.bullet", action: actions.showContents)
            Button("보기 설정", systemImage: "textformat.size", action: actions.showAppearance)
            Divider()
            Picker(selection: settings.$voiceID) {
                ForEach(ListeningVoice.all) { voice in
                    Text("\(voice.name) · \(voice.accent)").tag(voice.id)
                }
            } label: {
                Label("목소리: \(ListeningVoice.voice(id: settings.voiceID).name)", systemImage: "person.wave.2")
            }
            .pickerStyle(.menu)
            Picker(selection: settings.$speed) {
                ForEach(Self.speeds, id: \.self) { value in
                    Text(Self.speedText(value)).tag(value)
                }
            } label: {
                Label("속도: \(Self.speedText(settings.speed))", systemImage: "gauge.with.dots.needle.50percent")
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(appearance.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        #if os(macOS)
        .menuStyle(.button)
        .buttonStyle(.plain)
        #endif
        .fixedSize()
        .accessibilityLabel("더 보기")
    }

    static func speedText(_ value: Double) -> String {
        String(format: "%.1f×", value)
    }
}

/// 아래 막대: 진행률(%) 한 줄, 그 아래 이전 문장 · 재생/정지 · 다음 문장.
struct ReaderBottomBar: View {
    let session: ReaderSession
    let appearance: ReaderAppearance
    var safeBottom: CGFloat = 0

    private var isReady: Bool { session.speaker.modelState == .ready }

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f%%", session.progress * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(appearance.secondary)
            if let status = statusText {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(appearance.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: 36) {
                Button {
                    session.goPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(!session.canGoPrevious)
                .accessibilityLabel("이전 문장")

                Button {
                    session.togglePlayback()
                } label: {
                    Image(systemName: session.isSpeaking ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 52, height: 52)
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(!isReady)
                .accessibilityLabel(session.isSpeaking ? "정지" : "이 문장부터 듣기")

                Button {
                    session.goNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(!session.canGoNext)
                .accessibilityLabel("다음 문장")
            }
            .buttonStyle(.plain)
            .foregroundStyle(appearance.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, max(safeBottom, 8))
        .background(appearance.desk)
        .overlay(alignment: .top) {
            Rectangle().fill(appearance.border).frame(height: 1)
        }
    }

    /// 음성이 준비되지 않았을 때만 이유를 보인다.
    private var statusText: String? {
        switch session.speaker.modelState {
        case .loading: return "음성 준비 중…"
        case .unavailable(let reason): return reason
        case .ready: return nil
        }
    }
}

/// 막대가 숨어 있어도 동작하는 키: 스페이스 재생·정지, ←/→ 이전·다음 문장, ⌘D 북마크.
struct ReaderKeyboardShortcuts: View {
    let session: ReaderSession

    var body: some View {
        ZStack {
            Button("재생·정지") { session.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(session.speaker.modelState != .ready)
            Button("이전 문장") { session.goPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("다음 문장") { session.goNext() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("북마크") { session.toggleBookmark(at: session.position) }
                .keyboardShortcut("d", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 목소리·속도 설정을 읽기 상태에 맞춘다. 값은 `@AppStorage` 에 있다.
struct ReaderSpeechSettingsSync: ViewModifier {
    let session: ReaderSession
    let settings: ReaderSettingsBindings

    func body(content: Content) -> some View {
        content
            .onAppear {
                session.setVoice(ListeningVoice.voice(id: settings.voiceID))
                session.setSpeed(settings.speed)
            }
            .onChange(of: settings.voiceID) { _, id in session.setVoice(ListeningVoice.voice(id: id)) }
            .onChange(of: settings.speed) { _, value in session.setSpeed(value) }
    }
}
