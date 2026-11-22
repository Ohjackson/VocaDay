import SwiftUI
#if os(macOS)
import AppKit
typealias ReaderPlatformColor = NSColor
typealias ReaderPlatformFont = NSFont
#else
import UIKit
typealias ReaderPlatformColor = UIColor
typealias ReaderPlatformFont = UIFont
#endif

/// 책 화면 테마. 평평한 색 세 겹(책상 / 페이지 / 테두리 1pt)만으로 깊이를 낸다. 그림자·그라데이션·질감은 쓰지 않는다.
enum ReaderTheme: String, CaseIterable, Identifiable, Sendable {
    case oldBook
    case cream
    case paperWhite
    case sage
    case night

    var id: Self { self }

    var title: String {
        switch self {
        case .oldBook: return "오래된 책"
        case .cream: return "크림"
        case .paperWhite: return "종이 흰색"
        case .sage: return "연녹색"
        case .night: return "밤"
        }
    }

    var palette: ReaderPalette {
        switch self {
        case .oldBook:
            return ReaderPalette(desk: 0xCBBE9E, page: 0xEEE2C4, border: 0xD9C89F, text: 0x3A2E1F, secondary: 0x83725A, sentence: 0xE2CD93, word: 0x8A5A1F)
        case .cream:
            return ReaderPalette(desk: 0xE0D8C6, page: 0xF6EFDF, border: 0xE5DBC5, text: 0x2F2A24, secondary: 0x8B8173, sentence: 0xEEDFB3, word: 0x8A5A1F)
        case .paperWhite:
            return ReaderPalette(desk: 0xDEDCD5, page: 0xFBFAF6, border: 0xE8E5DC, text: 0x26251F, secondary: 0x8A887F, sentence: 0xF1E6B8, word: 0x2F5D8A)
        case .sage:
            return ReaderPalette(desk: 0xCFD3BE, page: 0xE8EBD7, border: 0xD5DAC0, text: 0x2E3324, secondary: 0x7A806A, sentence: 0xD9DFA9, word: 0x4F6B1F)
        case .night:
            return ReaderPalette(desk: 0x161412, page: 0x2A2622, border: 0x3A342D, text: 0xD9CDB6, secondary: 0x8E8372, sentence: 0x4A3F2A, word: 0xE0B56A)
        }
    }

    var colorScheme: ColorScheme { self == .night ? .dark : .light }
}

/// 테마 색. 값은 지시서 표 그대로 (0xRRGGBB).
nonisolated struct ReaderPalette: Hashable, Sendable {
    var desk: UInt32
    var page: UInt32
    var border: UInt32
    var text: UInt32
    var secondary: UInt32
    /// 읽는 문장 배경.
    var sentence: UInt32
    /// 누른 단어 글자·밑줄, 북마크 표시.
    var word: UInt32
}

extension ReaderPlatformColor {
    nonisolated convenience init(readerHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(readerHex hex: UInt32) {
        self.init(ReaderPlatformColor(readerHex: hex))
    }
}

/// 글자 크기·줄 간격·테마. 값은 `@AppStorage` 로 기기에 남긴다.
struct ReaderAppearance: Equatable {
    static let fontSizeRange: ClosedRange<Double> = 14...22
    static let lineHeightRange: ClosedRange<Double> = 1.3...2.0
    static let defaultFontSize = 17.0
    static let defaultLineHeight = 1.6

    var fontSize: Double
    /// 줄 높이 배수.
    var lineHeight: Double
    var theme: ReaderTheme

    var palette: ReaderPalette { theme.palette }
    var desk: Color { Color(readerHex: palette.desk) }
    var page: Color { Color(readerHex: palette.page) }
    var border: Color { Color(readerHex: palette.border) }
    var text: Color { Color(readerHex: palette.text) }
    var secondary: Color { Color(readerHex: palette.secondary) }
    /// 버튼·진행 막대 tint. 「누른 단어」 색과 같다.
    var accent: Color { Color(readerHex: palette.word) }
}

enum ReaderStorageKey {
    static let fontSize = "readerPageFontSize"
    static let lineHeight = "readerPageLineHeight"
    static let theme = "readerPageTheme"
    static let followsSystemDark = "readerFollowsSystemDark"
    /// 직접 넣은 글 듣기와 같은 값을 쓴다.
    static let voiceID = "listeningVoiceID"
    static let speed = "listeningSpeed"
}

/// 글자 크기·줄 간격·테마 조절. iPhone·Mac 모두 팝오버 안에 넣는다.
struct ReaderAppearanceControls: View {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var theme: ReaderTheme
    @Binding var followsSystemDark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("글자 크기")
                Spacer()
                Button {
                    fontSize = max(ReaderAppearance.fontSizeRange.lowerBound, fontSize - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 30, height: 26)
                }
                .accessibilityLabel("글자 작게")
                Text("\(Int(fontSize))pt")
                    .monospacedDigit()
                    .frame(minWidth: 40)
                Button {
                    fontSize = min(ReaderAppearance.fontSizeRange.upperBound, fontSize + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 30, height: 26)
                }
                .accessibilityLabel("글자 크게")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("줄 간격")
                    Spacer()
                    Text(String(format: "%.1f", lineHeight))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $lineHeight, in: ReaderAppearance.lineHeightRange, step: 0.1) {
                    Text("줄 간격")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("테마")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(ReaderTheme.allCases) { option in
                        themeSwatch(option)
                    }
                }
                Toggle("시스템이 다크 모드면 밤 테마", isOn: $followsSystemDark)
                    .font(.subheadline)
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    private func themeSwatch(_ option: ReaderTheme) -> some View {
        let palette = option.palette
        let isSelected = theme == option
        return Button {
            theme = option
        } label: {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Color(readerHex: palette.text))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color(readerHex: palette.page))
                    .overlay {
                        Rectangle().strokeBorder(Color(readerHex: palette.border), lineWidth: 1)
                    }
                    .padding(4)
                    .background(Color(readerHex: palette.desk))
                    .overlay {
                        Rectangle().strokeBorder(.tint, lineWidth: isSelected ? 2 : 0)
                    }
                Text(option.title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("테마 \(option.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
