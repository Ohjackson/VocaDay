import SwiftData
import SwiftUI

/// 데이 단어장. 읽기 모드에서는 줄을 누르면 예문이 펼쳐지고, 듣기 모드에서는 영단어 발음을 들려준다.
struct DayWordsDetailView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case read = "읽기"
        case listen = "듣기"

        var id: Self { self }

        var hint: String {
            switch self {
            #if os(macOS)
            case .read: "줄을 누르면 예문이 펼쳐져요. 우클릭하면 편집·삭제."
            #else
            case .read: "줄을 누르면 예문이 펼쳐져요. 길게 누르면 편집·삭제."
            #endif
            case .listen: "줄을 누르면 영단어 발음을 들려줘요."
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case added = "추가한 순서"
        case mostWrong = "많이 틀린 순"

        var id: Self { self }
    }

    let initialDay: VocabularyDay

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigate) private var navigate
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]
    @StateObject private var speechPlayer = DaySpeechPlayer()
    @State private var currentDayID: UUID
    @State private var mode: Mode = .read
    @State private var sort: Sort = .added
    @State private var showsOnlyIssues = false
    @State private var expandedWordID: UUID?
    @State private var wordPendingDeletion: VocaWord?
    @State private var searchText = ""
    @State private var errorAlert: VocaAlert?

    init(initialDay: VocabularyDay) {
        self.initialDay = initialDay
        _currentDayID = State(initialValue: initialDay.id)
    }

    private var currentDay: VocabularyDay {
        days.first { $0.id == currentDayID } ?? initialDay
    }

    /// 추가한 순서 기준 번호. 정렬·검색해도 번호는 그대로 둔다.
    private var addedOrder: [VocaWord] {
        currentDay.wordList.sorted { $0.createdAt < $1.createdAt }
    }

    private var issueWordIDs: Set<UUID> {
        Set(addedOrder.filter { !WordDataCheck.isQuizReady(WordDataCheck.issues(
            english: $0.english, meaningKo: $0.meaningKo, exampleEn: $0.exampleEn, exampleKo: $0.exampleKo
        )) }.map(\.id))
    }

    private var visibleWords: [VocaWord] {
        var words = addedOrder
        if sort == .mostWrong {
            words = words.enumerated()
                .sorted { $0.element.wrongCount == $1.element.wrongCount ? $0.offset < $1.offset : $0.element.wrongCount > $1.element.wrongCount }
                .map(\.element)
        }
        if showsOnlyIssues {
            let issues = issueWordIDs
            words = words.filter { issues.contains($0.id) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return words }
        return words.filter { word in
            [word.english, word.meaningKo, word.exampleEn, word.exampleKo, word.note, word.toeicTag]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        let numbers = Dictionary(uniqueKeysWithValues: addedOrder.enumerated().map { ($0.element.id, $0.offset + 1) })
        let words = visibleWords

        AppCollectionPage(maxContentWidth: 900, horizontalPadding: 16, verticalPadding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                controls

                if words.isEmpty {
                    EmptyStateView(title: emptyTitle, systemImage: "text.page")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                            if index > 0 {
                                Divider().padding(.leading, 54)
                            }
                            DayWordRow(
                                number: numbers[word.id] ?? index + 1,
                                word: word,
                                isExpanded: mode == .read && expandedWordID == word.id,
                                isSpeaking: speechPlayer.currentWordID == word.id,
                                tapSpeaks: mode == .listen,
                                onTap: { tap(word) },
                                onEdit: { edit(word) },
                                onSpeak: { speechPlayer.speakEnglishWord(word.english, wordID: word.id) },
                                onDelete: { wordPendingDeletion = word }
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                    .calmCard()
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle(currentDay.title)
        .searchable(text: $searchText, prompt: "단어 검색")
        .confirmationDialog(
            "‘\(wordPendingDeletion?.english ?? "")’을 삭제할까요?",
            isPresented: Binding(get: { wordPendingDeletion != nil }, set: { if !$0 { wordPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let word = wordPendingDeletion { delete(word) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("복습 기록도 함께 사라지고 되돌릴 수 없어요.")
        }
        .onChange(of: currentDayID) { _, _ in
            expandedWordID = nil
            showsOnlyIssues = false
        }
        .onChange(of: mode) { _, _ in
            speechPlayer.stop()
        }
        .onDisappear {
            speechPlayer.stop()
        }
        .alert(item: $errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    // MARK: 상단 조작

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("보기 방식", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)

                Spacer(minLength: 0)

                Button {
                    togglePlayback()
                } label: {
                    Label(speechPlayer.isPlaying ? "중지" : "전체 듣기", systemImage: speechPlayer.isPlaying ? "stop.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(visibleWords.isEmpty && !speechPlayer.isPlaying)
                .help("번호 · 단어 · 뜻 · 예문 순서로 이 데이를 끝까지 읽어요")
            }

            Text(mode.hint)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                summary
                Spacer(minLength: 0)
                Picker("정렬", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var summary: some View {
        let total = addedOrder.count
        let issueCount = issueWordIDs.count
        return HStack(spacing: 8) {
            Text("단어 \(total)개 · 문제 준비 \(total - issueCount)/\(total)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if issueCount > 0 || showsOnlyIssues {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showsOnlyIssues.toggle() }
                } label: {
                    Label(showsOnlyIssues ? "전체 보기" : "확인 필요 \(issueCount)", systemImage: showsOnlyIssues ? "list.bullet" : "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(showsOnlyIssues ? .accentColor : .orange)
            }
        }
    }

    private var emptyTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "일치하는 단어가 없습니다." }
        if showsOnlyIssues { return "확인이 필요한 단어가 없어요." }
        return "이 데이에 저장된 단어가 없습니다."
    }

    // MARK: 동작

    private func tap(_ word: VocaWord) {
        switch mode {
        case .read:
            withAnimation(.easeInOut(duration: 0.18)) {
                expandedWordID = expandedWordID == word.id ? nil : word.id
            }
        case .listen:
            speechPlayer.speakEnglishWord(word.english, wordID: word.id)
        }
    }

    private func edit(_ word: VocaWord) {
        speechPlayer.stop()
        navigate(.wordEdit(wordID: word.id))
    }

    private func togglePlayback() {
        if speechPlayer.isPlaying {
            speechPlayer.stop()
            return
        }

        let playingDay = currentDay
        speechPlayer.play(words: visibleWords) {
            moveToNextDay(after: playingDay)
        }
    }

    /// 전체 듣기가 끝나면 다음 데이로 넘어간다.
    private func moveToNextDay(after day: VocabularyDay) {
        guard let currentIndex = days.firstIndex(where: { $0.id == day.id }) else { return }
        let nextIndex = days.index(after: currentIndex)
        guard days.indices.contains(nextIndex) else { return }
        currentDayID = days[nextIndex].id
    }

    private func delete(_ word: VocaWord) {
        speechPlayer.stop()
        if expandedWordID == word.id {
            expandedWordID = nil
        }
        currentDay.removeWord(word)
        modelContext.delete(word)
        wordPendingDeletion = nil
        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
        }
    }
}
