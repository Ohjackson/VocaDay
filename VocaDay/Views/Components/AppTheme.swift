import SwiftUI

enum AppTheme {
    static let cardCornerRadius: CGFloat = 14
    static let innerCornerRadius: CGFloat = 10
    static let pageHorizontalPadding: CGFloat = 20
    static let pageVerticalPadding: CGFloat = 24
    static let cardPadding: CGFloat = 16

    static var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var softStroke: Color {
        Color.secondary.opacity(0.14)
    }

    static var raisedBackground: Color {
        Color.secondary.opacity(0.07)
    }
}

struct CalmCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppTheme.softStroke)
            }
            .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func calmCard() -> some View {
        modifier(CalmCardModifier())
    }
}
