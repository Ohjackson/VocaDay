import SwiftData
import SwiftUI

private enum StudyMemoFilter: String, CaseIterable, Identifiable {
    case all
    case lc
    case grammar
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .lc: "LC"
        case .grammar: "문법"
        case .general: "일반"
        }
    }

    func includes(_ memo: StudyMemo) -> Bool {
        switch self {
        case .all: true
        case .lc: memo.type == .lcDictation
        case .grammar: memo.type == .grammar
        case .general: memo.type == .general
        }
    }
}

struct StudyMemosView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyMemo.updatedAt, order: .reverse) private var memos: [StudyMemo]

    @State private var searchText = ""
    @State private var filter: StudyMemoFilter = .all
    @State private var isShowingTemplatePicker = false
    @State private var selectedMemoID: UUID?
    @State private var memoPendingDeletion: StudyMemo?

    private var filteredMemos: [StudyMemo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return memos
            .filter { memo in
                filter.includes(memo) &&
                (query.isEmpty || memo.searchableText.localizedCaseInsensitiveContains(query))
            }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("메모 유형", selection: $filter) {
                    ForEach(StudyMemoFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onboardingSpotlight(.studyMemos)

                if memos.isEmpty {
                    emptyMemosView
                } else if filteredMemos.isEmpty {
                    EmptyStateView(
                        title: "조건에 맞는 학습 메모가 없습니다.",
                        systemImage: "magnifyingglass"
                    )
                    .padding(.top, 36)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredMemos) { memo in
                            Button {
                                selectedMemoID = memo.id
                            } label: {
                                StudyMemoCard(memo: memo)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    memo.isPinned.toggle()
                                    memo.updatedAt = Date()
                                    try? modelContext.save()
                                } label: {
                                    Label(memo.isPinned ? "고정 해제" : "상단에 고정", systemImage: memo.isPinned ? "pin.slash" : "pin")
                                }

                                Button(role: .destructive) {
                                    memoPendingDeletion = memo
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 840, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("학습 메모")
        .searchable(text: $searchText, prompt: "제목, 내용 또는 태그 검색")
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button {
                    isShowingTemplatePicker = true
                } label: {
                    Label("새 학습 메모", systemImage: "plus")
                }
                .accessibilityHint("LC 받아쓰기, 문법 정리 또는 자유 메모를 만듭니다")
            }
        }
        .sheet(isPresented: $isShowingTemplatePicker) {
            StudyMemoTemplatePicker { type in
                createMemo(type: type)
            }
        }
        .navigationDestination(item: $selectedMemoID) { memoID in
            if let memo = memos.first(where: { $0.id == memoID }) {
                StudyMemoEditorView(memo: memo)
            } else {
                ContentUnavailableView("메모를 찾을 수 없습니다", systemImage: "note.text")
            }
        }
        .confirmationDialog(
            "이 학습 메모를 삭제할까요?",
            isPresented: Binding(
                get: { memoPendingDeletion != nil },
                set: { if !$0 { memoPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive, action: deletePendingMemo)
            Button("취소", role: .cancel) { memoPendingDeletion = nil }
        } message: {
            Text("삭제한 메모는 복구할 수 없습니다.")
        }
    }

    private var emptyMemosView: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                title: "아직 학습 메모가 없습니다.",
                systemImage: "note.text.badge.plus"
            )

            Text("외부 음원을 들으며 LC를 받아쓰거나, 문법과 학습 내용을 나만의 방식으로 정리해 보세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Button {
                isShowingTemplatePicker = true
            } label: {
                Label("첫 학습 메모 만들기", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func createMemo(type: StudyMemoType) {
        let memo = StudyMemo(type: type, title: "새 \(type.title)")
        modelContext.insert(memo)
        try? modelContext.save()
        isShowingTemplatePicker = false

        Task { @MainActor in
            await Task.yield()
            selectedMemoID = memo.id
        }
    }

    private func deletePendingMemo() {
        guard let memoPendingDeletion else { return }
        modelContext.delete(memoPendingDeletion)
        try? modelContext.save()
        self.memoPendingDeletion = nil
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

private struct StudyMemoCard: View {
    let memo: StudyMemo

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: memo.type.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(memo.title.isEmpty ? "제목 없는 메모" : memo.title)
                        .font(.headline)
                        .lineLimit(1)

                    if memo.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }

                    Spacer(minLength: 8)

                    Text(memo.type.shortTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(memo.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if memo.needsReview {
                        Label("복습 필요", systemImage: "arrow.clockwise")
                            .foregroundStyle(.orange)
                    }

                    if !memo.tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(memo.tags, systemImage: "tag")
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(memo.updatedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calmCard()
    }
}

private struct StudyMemoTemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (StudyMemoType) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(StudyMemoType.allCases) { type in
                        Button {
                            onSelect(type)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: type.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 44, height: 44)
                                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(type.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .calmCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("새 학습 메모")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct StudyMemoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var memo: StudyMemo

    @State private var isAnswerExpanded = false
    @State private var showsDeleteConfirmation = false
    @State private var saveTask: Task<Void, Never>?

    private var editSignature: String {
        [
            memo.title, memo.body, memo.dictationText, memo.answerText, memo.translation,
            memo.note, memo.source, memo.tags, memo.typeRawValue,
            memo.isPinned.description, memo.needsReview.description
        ].joined(separator: "\u{1F}")
    }

    var body: some View {
        Form {
            Section("기본 정보") {
                TextField("메모 제목", text: $memo.title)

                Picker("메모 유형", selection: $memo.typeRawValue) {
                    ForEach(StudyMemoType.allCases) { type in
                        Label(type.title, systemImage: type.systemImage)
                            .tag(type.rawValue)
                    }
                }
            }

            contentSections

            Section("분류 및 복습") {
                TextField("태그 (예: 토익, Part 3)", text: $memo.tags)

                Toggle("상단에 고정", isOn: $memo.isPinned)
                Toggle("다시 복습할 메모", isOn: $memo.needsReview)
            }

            Section {
                LabeledContent("만든 날짜") {
                    Text(memo.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("최근 수정") {
                    Text(memo.updatedAt, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(memo.title.isEmpty ? memo.type.title : memo.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("학습 메모 삭제")
            }
        }
        .confirmationDialog("이 학습 메모를 삭제할까요?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("삭제", role: .destructive, action: deleteMemo)
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 메모는 복구할 수 없습니다.")
        }
        .onChange(of: editSignature) { _, _ in
            memo.updatedAt = Date()
            scheduleSave()
        }
        .onDisappear {
            saveTask?.cancel()
            try? modelContext.save()
        }
    }

    @ViewBuilder
    private var contentSections: some View {
        switch memo.type {
        case .lcDictation:
            Section {
                Label("VocaDay가 음원이나 정답을 제공하지 않습니다. 외부 강의·영상·음원을 들으며 직접 입력하세요.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("출처") {
                TextField("강의, 영상, 회차 또는 링크", text: $memo.source)
            }

            Section("내가 받아쓴 문장") {
                MemoTextEditor(text: $memo.dictationText, prompt: "들리는 영어 문장을 먼저 입력하세요.", minimumHeight: 130)
            }

            Section {
                DisclosureGroup("정답 문장 입력·확인", isExpanded: $isAnswerExpanded) {
                    MemoTextEditor(text: $memo.answerText, prompt: "외부 자료에서 확인한 정답 문장을 입력하세요.", minimumHeight: 110)
                        .padding(.top, 8)

                    if comparisonScore != nil {
                        HStack {
                            Text("단어 순서 기준 일치도")
                            Spacer()
                            Text("\(comparisonScore ?? 0)%")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        ProgressView(value: Double(comparisonScore ?? 0), total: 100)
                    }
                }
            } footer: {
                Text("먼저 받아쓰기를 끝낸 뒤 펼쳐서 비교하세요.")
            }

            Section("한국어 뜻") {
                MemoTextEditor(text: $memo.translation, prompt: "문장의 자연스러운 뜻을 입력하세요.", minimumHeight: 90)
            }

            Section("틀린 표현과 메모") {
                MemoTextEditor(text: $memo.note, prompt: "놓친 단어, 연음, 발음이나 다시 들을 부분을 기록하세요.", minimumHeight: 110)
            }

        case .grammar:
            Section("핵심 설명") {
                MemoTextEditor(text: $memo.body, prompt: "이 문법을 한두 문장으로 설명해 보세요.", minimumHeight: 120)
            }

            Section("형태 또는 공식") {
                MemoTextEditor(text: $memo.answerText, prompt: "예: have/has + 과거분사", minimumHeight: 80)
            }

            Section("영어 예문") {
                MemoTextEditor(text: $memo.dictationText, prompt: "문법이 사용된 영어 예문을 입력하세요.", minimumHeight: 100)
            }

            Section("예문 해석") {
                MemoTextEditor(text: $memo.translation, prompt: "영어 예문의 자연스러운 해석을 입력하세요.", minimumHeight: 90)
            }

            Section("주의점과 암기 메모") {
                MemoTextEditor(text: $memo.note, prompt: "헷갈리는 표현, 예외나 암기 포인트를 기록하세요.", minimumHeight: 110)
            }

        case .general:
            Section("메모") {
                MemoTextEditor(text: $memo.body, prompt: "학습한 내용, 질문이나 다음에 확인할 내용을 자유롭게 입력하세요.", minimumHeight: 300)
            }
        }
    }

    private var comparisonScore: Int? {
        let entered = words(in: memo.dictationText)
        let answer = words(in: memo.answerText)
        guard !entered.isEmpty, !answer.isEmpty else { return nil }

        var lengths = Array(repeating: 0, count: answer.count + 1)
        for enteredWord in entered {
            var previous = 0
            for index in answer.indices {
                let saved = lengths[index + 1]
                if enteredWord == answer[index] {
                    lengths[index + 1] = previous + 1
                } else {
                    lengths[index + 1] = max(lengths[index + 1], lengths[index])
                }
                previous = saved
            }
        }

        return Int((Double(lengths.last ?? 0) / Double(max(entered.count, answer.count)) * 100).rounded())
    }

    private func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            try? modelContext.save()
        }
    }

    private func deleteMemo() {
        saveTask?.cancel()
        modelContext.delete(memo)
        try? modelContext.save()
        dismiss()
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

private struct MemoTextEditor: View {
    @Binding var text: String
    let prompt: String
    let minimumHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(prompt)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minimumHeight)
        }
    }
}

#Preview {
    NavigationStack {
        StudyMemosView()
    }
    .modelContainer(for: [StudyMemo.self], inMemory: true)
}
