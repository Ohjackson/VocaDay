import SwiftData
import SwiftUI

/// 단어 편집. 초안을 고치다가 [저장]할 때만 단어에 반영하므로, 뒤로 가면 바뀌지 않는다.
/// 복습 일정(SRS) 필드는 건드리지 않는다.
struct WordEditView: View {
    let wordID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var words: [VocaWord]

    @State private var draft = Draft()
    @State private var hasLoaded = false
    @State private var errorAlert: VocaAlert?

    init(wordID: UUID) {
        self.wordID = wordID
        _words = Query(filter: #Predicate<VocaWord> { $0.id == wordID })
    }

    fileprivate struct Draft: Equatable {
        var english = ""
        var meaningKo = ""
        var exampleEn = ""
        var exampleKo = ""
        var note = ""
        var toeicTag = ""
    }

    var body: some View {
        if let word = words.first {
            form(for: word)
        } else {
            ContentUnavailableView("단어를 찾을 수 없습니다", systemImage: "textformat")
        }
    }

    private func form(for word: VocaWord) -> some View {
        Form {
            Section("단어") {
                labeledField("영단어", text: $draft.english)
                labeledField("뜻", text: $draft.meaningKo, prompt: "n. 뜻, v. 뜻")
            }

            Section {
                TextField("The meeting was postponed.", text: $draft.exampleEn, axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("영어 예문")
            } footer: {
                Text("품사가 여럿이면 1. / 2. 로 줄을 나눠요.")
            }

            Section {
                TextField("회의가 연기되었다.", text: $draft.exampleKo, axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("예문 번역")
            } footer: {
                WordDataCheckView(issues: WordDataCheck.issues(
                    english: draft.english,
                    meaningKo: draft.meaningKo,
                    exampleEn: draft.exampleEn,
                    exampleKo: draft.exampleKo
                ))
            }

            Section("기타") {
                labeledField("메모", text: $draft.note)
                labeledField("태그", text: $draft.toeicTag, prompt: "TOEIC 태그")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(word.english.isEmpty ? "단어 편집" : word.english)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") { save(word) }
                    .disabled(draft.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft == Draft(word))
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            draft = Draft(word)
            hasLoaded = true
        }
        .alert(item: $errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, prompt: String? = nil) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(prompt ?? title))
                .multilineTextAlignment(.trailing)
        }
    }

    private func save(_ word: VocaWord) {
        word.english = draft.english.trimmingCharacters(in: .whitespacesAndNewlines)
        word.meaningKo = draft.meaningKo
        word.exampleEn = draft.exampleEn
        word.exampleKo = draft.exampleKo
        word.note = draft.note
        word.toeicTag = draft.toeicTag
        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
            return
        }
        dismiss()
    }
}

fileprivate extension WordEditView.Draft {
    init(_ word: VocaWord) {
        self.init(
            english: word.english,
            meaningKo: word.meaningKo,
            exampleEn: word.exampleEn,
            exampleKo: word.exampleKo,
            note: word.note,
            toeicTag: word.toeicTag
        )
    }
}
