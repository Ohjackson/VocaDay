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

    static func url(for term: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-'"))
        guard let escaped = term.addingPercentEncoding(withAllowedCharacters: allowed), !escaped.isEmpty else { return nil }
        return URL(string: "dict://\(escaped)")
    }
}

#if os(iOS)
/// `UIReferenceLibraryViewController`를 SwiftUI 시트에 넣는다. 사전이 없으면 사전 내려받기 안내가 보인다.
struct SystemDictionarySheet: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
#endif
