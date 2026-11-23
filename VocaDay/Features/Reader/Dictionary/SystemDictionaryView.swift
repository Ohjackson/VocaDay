import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 기기에 들어 있는 사전(Apple 사전). 뜻 상자의 단어 글자를 누르면 연다.
/// iPhone: 사전 화면을 시트로. Mac: 사전 앱을 `dict://`로 연다.
enum SystemDictionary {
    /// 기기 사전에 이 단어가 있는지. 뜻 상자 오른쪽 위 표시에 쓴다.
    @MainActor
    static func hasDefinition(for term: String) -> Bool {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return false }
        #if os(iOS)
        return UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term)
        #else
        return SystemDictionaryLookupStep.systemDefinition(term) != nil
        #endif
    }

    /// 책 테마가 덮어쓴 값이 아니라 기기 화면의 실제 모드. 시스템 창(사전·번역 언어 팩 받기)은 이 모드로 그려진다.
    static var deviceColorScheme: ColorScheme {
        #if os(iOS)
        SystemDictionarySheet.deviceStyle == .dark ? .dark : .light
        #else
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        #endif
    }

    static func url(for term: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-'"))
        guard let escaped = term.addingPercentEncoding(withAllowedCharacters: allowed), !escaped.isEmpty else { return nil }
        return URL(string: "dict://\(escaped)")
    }
}

#if os(iOS)
/// `UIReferenceLibraryViewController`를 SwiftUI 시트에 넣는다. 사전이 없으면 사전 내려받기 안내가 보인다.
/// 사전 화면은 기기 화면 모드(라이트·다크)를 그대로 따른다.
/// 뜻 상자는 책 테마에 맞춰 색 모드를 바꿔 두므로, 그대로 물려받으면 다크 모드에서 글자와 바탕이 섞여 안 보였다.
struct SystemDictionarySheet: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        let controller = UIReferenceLibraryViewController(term: term)
        controller.overrideUserInterfaceStyle = Self.deviceStyle
        return controller
    }

    /// 책 테마가 덮어쓴 값이 아니라 기기 화면의 실제 모드.
    static var deviceStyle: UIUserInterfaceStyle {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.traitCollection.userInterfaceStyle ?? .unspecified
    }

    static var deviceColorScheme: ColorScheme { SystemDictionary.deviceColorScheme }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
#endif
