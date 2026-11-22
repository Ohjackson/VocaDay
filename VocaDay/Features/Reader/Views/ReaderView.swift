import SwiftUI

/// `AppRoute.book(id:)` 의 화면. 책을 찾아 읽기 상태를 만들고 iPhone·Mac 화면을 고른다.
struct ReaderView: View {
    let bookID: String

    @Environment(\.readingStore) private var store
    @State private var session: ReaderSession?

    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage(ReaderStorageKey.fontSize) private var fontSize = ReaderAppearance.defaultFontSize
    @AppStorage(ReaderStorageKey.lineHeight) private var lineHeight = ReaderAppearance.defaultLineHeight
    @AppStorage(ReaderStorageKey.theme) private var theme = ReaderTheme.oldBook
    @AppStorage(ReaderStorageKey.followsSystemDark) private var followsSystemDark = false
    @AppStorage(ReaderStorageKey.voiceID) private var voiceID = ListeningVoice.fallback.id
    @AppStorage(ReaderStorageKey.speed) private var speed = 1.0

    var body: some View {
        Group {
            if let session {
                let settings = ReaderSettingsBindings(
                    fontSize: $fontSize,
                    lineHeight: $lineHeight,
                    theme: $theme,
                    followsSystemDark: $followsSystemDark,
                    voiceID: $voiceID,
                    speed: $speed,
                    systemIsDark: systemColorScheme == .dark
                )
                #if os(macOS)
                ReaderMacView(session: session, settings: settings)
                #else
                ReaderPhoneView(session: session, settings: settings)
                #endif
            } else if ReaderBooks.book(id: bookID) == nil {
                ContentUnavailableView("책을 찾을 수 없습니다", systemImage: "book.closed")
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard session == nil, let book = ReaderBooks.book(id: bookID) else { return }
            session = ReaderSession(book: book, store: store)
        }
        .task(id: session != nil) {
            await session?.speaker.prepare()
        }
        .onDisappear {
            session?.stop()
        }
    }
}

/// 화면 설정 값 묶음. 값은 `ReaderView` 의 `@AppStorage` 에 있다.
struct ReaderSettingsBindings {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var theme: ReaderTheme
    @Binding var followsSystemDark: Bool
    @Binding var voiceID: String
    @Binding var speed: Double
    /// 책 화면은 테마 색을 칠하려고 colorScheme 을 덮어쓴다. 그래서 시스템 값은 덮기 전에 읽어 넘긴다.
    var systemIsDark: Bool

    var appearance: ReaderAppearance {
        ReaderAppearance(
            fontSize: fontSize.clamped(to: ReaderAppearance.fontSizeRange),
            lineHeight: lineHeight.clamped(to: ReaderAppearance.lineHeightRange),
            theme: followsSystemDark && systemIsDark ? .night : theme
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
