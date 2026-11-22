import SwiftUI

/// 보고서 숫자·문구 표기. 배지와 상세 화면이 같이 쓴다.
nonisolated enum BookFitFormat {
    static func percent(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", value * 100)
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func perThousand(_ value: Double) -> String {
        String(format: "%.0f", value.rounded())
    }

    static func position(_ position: ReadingPosition) -> String {
        "\(position.chapter + 1)장 \(position.paragraph + 1)문단 \(position.sentence + 1)문장"
    }

    static func color(_ verdict: BookFitVerdict) -> Color {
        switch verdict {
        case .extensive: .green
        case .intensive: .blue
        case .notYet: .orange
        }
    }

    static func symbol(_ verdict: BookFitVerdict) -> String {
        switch verdict {
        case .extensive: "hare"
        case .intensive: "magnifyingglass"
        case .notYet: "hourglass"
        }
    }
}

/// 판정 알약 하나.
struct BookFitVerdictPill: View {
    let verdict: BookFitVerdict

    var body: some View {
        Label(verdict.title, systemImage: BookFitFormat.symbol(verdict))
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(BookFitFormat.color(verdict))
            .background(BookFitFormat.color(verdict).opacity(0.14), in: Capsule())
            .accessibilityLabel("판정 \(verdict.title)")
    }
}
