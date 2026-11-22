import SwiftUI

/// 책 id 로 책을 찾는다. 앱에 들어 있는 책을 먼저 보고, 없으면 PDF 로 가져온 책을 본다.
@MainActor
enum ReaderBooks {
    static func book(id: String) -> BookDocument? {
        BookLibrary.book(id: id) ?? ImportedBookStore.shared.book(id: id)
    }
}

/// `AppRoute.pdfImport` 의 화면. 가져온 책을 열면 책 화면으로 간다.
struct PDFImportRouteScreen: View {
    @Environment(\.appNavigate) private var navigate

    var body: some View {
        BookImportView(onOpen: { bookID in
            navigate(.book(id: bookID))
        })
    }
}

/// `AppRoute.bookFit(bookID:)` 의 화면.
struct BookFitRouteScreen: View {
    let bookID: String

    var body: some View {
        if let book = ReaderBooks.book(id: bookID) {
            BookFitDetailScreen(book: book)
        } else {
            ContentUnavailableView("책을 찾을 수 없습니다", systemImage: "book.closed")
        }
    }
}
