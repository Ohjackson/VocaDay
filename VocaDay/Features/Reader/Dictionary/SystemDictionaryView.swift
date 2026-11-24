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

    private static var definitionCache: [String: Bool] = [:]

    /// `hasDefinition`을 기억해 두고 쓴다. 같은 단어를 다시 눌러도 사전을 다시 뒤지지 않는다.
    static func cachedHasDefinition(for term: String) -> Bool {
        let key = term.lowercased()
        if let cached = definitionCache[key] { return cached }
        let found = hasDefinition(for: term)
        definitionCache[key] = found
        return found
    }

    #if os(macOS)
    private static var articleCache: [String: SystemDictionaryArticle] = [:]

    /// 사전 글을 품사·뜻·예문으로 나눈 것. 사전에 없으면 nil.
    static func article(for term: String) -> SystemDictionaryArticle? {
        let key = term.lowercased()
        if let cached = articleCache[key] { return cached }
        let article = SystemDictionaryLookupStep.systemDefinition(term).flatMap(SystemDictionaryArticle.init)
        articleCache[key] = article
        return article
    }
    #endif

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

/// 단어 카드 안에 펼치는 사전. 사전 화면을 카드의 일부로 넣는다.
struct InlineSystemDictionary: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> InlineSystemDictionaryController {
        InlineSystemDictionaryController(term: term)
    }

    func updateUIViewController(_ controller: InlineSystemDictionaryController, context: Context) {}
}

/// 사전 화면 위쪽의 제목과 X를 가린다. 카드에 이미 단어가 있고, X는 사전이 아니라 바깥 화면(책)을 닫아 버린다.
final class InlineSystemDictionaryController: UIViewController {
    /// 사전 화면의 제목 줄 높이.
    private static let headerHeight: CGFloat = 64
    private let dictionary: UIReferenceLibraryViewController

    init(term: String) {
        dictionary = UIReferenceLibraryViewController(term: term)
        super.init(nibName: nil, bundle: nil)
        // 사전 글자는 기기 모드로 그려진다. 책 테마를 따르면 글자와 바탕이 섞인다.
        overrideUserInterfaceStyle = SystemDictionarySheet.deviceStyle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = HeaderBlockingView()
        view.clipsToBounds = true
        view.backgroundColor = .systemBackground
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(dictionary)
        view.addSubview(dictionary.view)
        dictionary.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dictionary.view.frame = CGRect(
            x: 0, y: -Self.headerHeight,
            width: view.bounds.width, height: view.bounds.height + Self.headerHeight
        )
    }

    /// X의 터치 영역은 보이는 것보다 아래까지 내려온다. 맨 위 터치는 사전에 넘기지 않는다.
    private final class HeaderBlockingView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            point.y < 16 && bounds.contains(point) ? self : super.hitTest(point, with: event)
        }
    }
}
#endif
