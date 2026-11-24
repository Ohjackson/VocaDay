import SwiftUI

/// 문장을 길게 누르면 그 문장 옆에 뜨는 카드: 번역 → 듣기·북마크·복사.
/// 영어 문장은 본문에 칠해져 있으므로 카드에는 넣지 않는다.
/// 단어 카드(`WordLookupCard`)와 같은 상자(`ReaderFloatingCard`)로 띄우지만 사전·저장은 없다.
struct ReaderSentenceCard: View {
    let session: ReaderSession
    let position: ReadingPosition

    @State private var contentHeight: CGFloat = 160
    @State private var copied = false

    private var sentence: BookSentence? { session.book.sentence(at: position) }
    private var isBookmarked: Bool { session.bookmark(at: position) != nil }

    var body: some View {
        // 긴 문장은 잘리지 않고 스크롤된다 (단어 카드와 같은 방식).
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let translation = sentence?.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("아직 번역이 없는 문장이에요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                buttons
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: 300, maxWidth: .infinity, idealHeight: contentHeight, maxHeight: contentHeight)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button {
                session.activeSentence = nil
                session.play(from: position)
            } label: {
                Label("이 문장부터 듣기", systemImage: "play.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 20)
            }
            .disabled(session.speaker.modelState != .ready)

            Button {
                session.toggleBookmark(at: position)
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .frame(width: 20, height: 20)
            }
            .accessibilityLabel(isBookmarked ? "북마크 삭제" : "북마크")

            Button {
                if let text = sentence?.text { ReaderPasteboard.copy(text) }
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 20)
            }
            .accessibilityLabel(copied ? "복사됨" : "문장 복사")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .font(.subheadline.weight(.semibold))
    }
}
