import SwiftData
import SwiftUI

struct StudyMemosView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyMemo.updatedAt, order: .reverse) private var memos: [StudyMemo]

    @State private var searchText = ""
    @State private var selectedMemoID: UUID?
    @State private var memoPendingDeletion: StudyMemo?

    private var filteredMemos: [StudyMemo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return memos
            .filter { query.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(query) }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var pinnedMemos: [StudyMemo] { filteredMemos.filter(\.isPinned) }
    private var regularMemos: [StudyMemo] { filteredMemos.filter { !$0.isPinned } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                pageListHeader
                    .onboardingSpotlight(.studyMemos)

                if memos.isEmpty {
                    emptyPagesView
                } else if filteredMemos.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 44)
                } else {
                    if !pinnedMemos.isEmpty {
                        pageSection(title: "고정", pages: pinnedMemos)
                    }
                    if !regularMemos.isEmpty {
                        pageSection(title: pinnedMemos.isEmpty ? "페이지" : "나의 페이지", pages: regularMemos)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 26)
            .frame(maxWidth: 920, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(NotionStyle.pageBackground)
        .navigationTitle("학습 메모")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "페이지 검색")
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button(action: createPage) {
                    Label("새 페이지", systemImage: "square.and.pencil")
                }
                .accessibilityHint("빈 학습 페이지를 바로 만듭니다")
            }
        }
        .navigationDestination(item: $selectedMemoID) { memoID in
            if let memo = memos.first(where: { $0.id == memoID }) {
                StudyPageEditorView(memo: memo)
            } else {
                ContentUnavailableView("페이지를 찾을 수 없습니다", systemImage: "doc.text")
            }
        }
        .confirmationDialog(
            "이 페이지를 삭제할까요?",
            isPresented: Binding(
                get: { memoPendingDeletion != nil },
                set: { if !$0 { memoPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive, action: deletePendingMemo)
            Button("취소", role: .cancel) { memoPendingDeletion = nil }
        } message: {
            Text("삭제한 페이지는 복구할 수 없습니다.")
        }
        .task {
            migrateLegacyPages()
        }
    }

    private var pageListHeader: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("나의 페이지")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("배운 내용을 블록으로 자유롭게 정리하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: createPage) {
                Label("새 페이지", systemImage: "plus")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func pageSection(title: String, pages: [StudyMemo]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            ForEach(pages) { memo in
                Button {
                    selectedMemoID = memo.id
                } label: {
                    StudyPageListRow(memo: memo)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        memo.isPinned.toggle()
                        memo.updatedAt = Date()
                        try? modelContext.save()
                    } label: {
                        Label(memo.isPinned ? "고정 해제" : "고정", systemImage: memo.isPinned ? "pin.slash" : "pin")
                    }

                    Button {
                        duplicate(memo)
                    } label: {
                        Label("복제", systemImage: "plus.square.on.square")
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

    private var emptyPagesView: some View {
        VStack(spacing: 18) {
            Text("📝")
                .font(.system(size: 54))
            Text("첫 페이지를 만들어 보세요")
                .font(.title3.weight(.semibold))
            Text("유형을 고를 필요 없이 빈 페이지에서 시작합니다.\n텍스트를 입력하거나 /를 입력해 블록을 추가하세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("새 페이지") { createPage() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private func createPage() {
        let memo = StudyMemo(title: "", icon: "📄", blocks: [StudyPageBlock()])
        modelContext.insert(memo)
        try? modelContext.save()
        selectedMemoID = memo.id
    }

    private func duplicate(_ source: StudyMemo) {
        let copy = StudyMemo(
            title: source.title.isEmpty ? "페이지 복사본" : "\(source.title) 복사본",
            icon: source.icon,
            coverStyle: source.coverStyle,
            blocks: source.blocks,
            isPinned: false,
            needsReview: source.needsReview
        )
        modelContext.insert(copy)
        try? modelContext.save()
        selectedMemoID = copy.id
    }

    private func migrateLegacyPages() {
        var changed = false
        for memo in memos where memo.migrateLegacyContentIfNeeded() {
            changed = true
        }
        if changed { try? modelContext.save() }
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

private struct StudyPageListRow: View {
    let memo: StudyMemo
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 13) {
            Text(memo.icon.isEmpty ? "📄" : memo.icon)
                .font(.title2)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(memo.title.isEmpty ? "제목 없음" : memo.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if memo.needsReview {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Text(memo.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(memo.updatedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isHovering ? NotionStyle.hoverBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct StudyPageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var memo: StudyMemo

    @State private var blocks: [StudyPageBlock]
    @State private var slashTargetID: UUID?
    @State private var showsDeleteConfirmation = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focusedBlockID: UUID?

    init(memo: StudyMemo) {
        self.memo = memo
        _blocks = State(initialValue: memo.blocks)
    }

    private var changeSignature: String {
        let blockData = (try? JSONEncoder().encode(blocks)) ?? Data()
        return [memo.title, memo.icon, memo.coverStyle, memo.isPinned.description, memo.needsReview.description, blockData.base64EncodedString()]
            .joined(separator: "\u{1F}")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if memo.coverStyle != "none" {
                    PageCover(style: memo.coverStyle)
                        .frame(height: 170)
                        .overlay(alignment: .topTrailing) {
                            coverMenu
                                .padding(14)
                        }
                }

                VStack(alignment: .leading, spacing: 0) {
                    pageActions
                        .padding(.bottom, 10)

                    Menu {
                        ForEach(pageIcons, id: \.self) { icon in
                            Button(icon) { memo.icon = icon }
                        }
                    } label: {
                        Text(memo.icon.isEmpty ? "📄" : memo.icon)
                            .font(.system(size: 66))
                            .frame(width: 82, height: 82)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("페이지 아이콘 변경")

                    TextField("제목 없음", text: $memo.title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 40, weight: .bold))
                        .lineLimit(1...3)
                        .padding(.bottom, 18)

                    VStack(spacing: 1) {
                        ForEach($blocks) { $block in
                            StudyPageBlockRow(
                                block: $block,
                                number: listNumber(for: block.id),
                                focusedBlockID: $focusedBlockID,
                                onInsertAfter: { kind in insertBlock(after: block.id, kind: kind) },
                                onDuplicate: { duplicateBlock(block.id) },
                                onDelete: { deleteBlock(block.id) },
                                onTransform: { transformBlock(block.id, to: $0) },
                                onMove: { direction in moveBlock(block.id, direction: direction) },
                                onSlashCommand: { openSlashMenu(for: block.id) },
                                onDropBlock: moveBlock(sourceID:before:)
                            )
                        }
                    }

                    Button {
                        insertBlock(after: blocks.last?.id, kind: .text)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("블록 추가")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, memo.coverStyle == "none" ? 28 : 0)
                .padding(.bottom, 120)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(NotionStyle.editorBackground)
        .navigationTitle(memo.title.isEmpty ? "제목 없음" : memo.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Button {
                    memo.isPinned.toggle()
                } label: {
                    Image(systemName: memo.isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(memo.isPinned ? "고정 해제" : "페이지 고정")

                Menu {
                    Toggle("복습 필요", isOn: $memo.needsReview)
                    Divider()
                    Button("페이지 삭제", role: .destructive) { showsDeleteConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { slashTargetID != nil },
            set: { if !$0 { slashTargetID = nil } }
        )) {
            BlockCommandMenu { kind in
                guard let slashTargetID else { return }
                transformBlock(slashTargetID, to: kind)
                self.slashTargetID = nil
            }
        }
        .confirmationDialog("이 페이지를 삭제할까요?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("삭제", role: .destructive, action: deletePage)
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 페이지는 복구할 수 없습니다.")
        }
        .onChange(of: changeSignature) { _, _ in
            persistChanges()
        }
        .onDisappear {
            saveTask?.cancel()
            memo.setBlocks(blocks)
            try? modelContext.save()
        }
    }

    private var pageActions: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(pageIcons, id: \.self) { icon in
                    Button("\(icon)  \(iconName(icon))") { memo.icon = icon }
                }
            } label: {
                Label("아이콘 변경", systemImage: "face.smiling")
            }

            coverMenu
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    private var coverMenu: some View {
        Menu {
            Button("커버 없음") { memo.coverStyle = "none" }
            Divider()
            ForEach(PageCoverStyle.allCases.filter { $0 != .none }) { style in
                Button(style.title) { memo.coverStyle = style.rawValue }
            }
        } label: {
            Label(memo.coverStyle == "none" ? "커버 추가" : "커버 변경", systemImage: "photo")
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func listNumber(for blockID: UUID) -> Int {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return 1 }
        var count = 1
        for previous in blocks[..<index].reversed() {
            guard previous.kind == .numberedList else { break }
            count += 1
        }
        return count
    }

    private func insertBlock(after blockID: UUID?, kind: StudyPageBlockKind) {
        let newBlock = kind == .table ? StudyPageBlock.table() : StudyPageBlock(kind: kind)
        if let blockID, let index = blocks.firstIndex(where: { $0.id == blockID }) {
            blocks.insert(newBlock, at: index + 1)
        } else {
            blocks.append(newBlock)
        }
        focus(newBlock.id, unless: kind == .divider || kind == .table)
    }

    private func duplicateBlock(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        var copy = blocks[index]
        copy.id = UUID()
        blocks.insert(copy, at: index + 1)
        focus(copy.id, unless: copy.kind == .divider || copy.kind == .table)
    }

    private func deleteBlock(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        if blocks.count == 1 {
            blocks[0] = StudyPageBlock()
            focusedBlockID = blocks[0].id
            return
        }
        blocks.remove(at: index)
        focusedBlockID = blocks[min(index, blocks.count - 1)].id
    }

    private func transformBlock(_ id: UUID, to kind: StudyPageBlockKind) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].kind = kind
        if blocks[index].text == "/" { blocks[index].text = "" }
        if kind == .table && blocks[index].tableColumns.isEmpty {
            blocks[index].tableColumns = ["열 1", "열 2"]
            blocks[index].tableRows = [["", ""], ["", ""]]
        }
        focus(id, unless: kind == .divider || kind == .table)
    }

    private func moveBlock(_ id: UUID, direction: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + direction
        guard blocks.indices.contains(destination) else { return }
        blocks.swapAt(index, destination)
    }

    private func moveBlock(sourceID: UUID, before targetID: UUID) -> Bool {
        guard sourceID != targetID,
              let source = blocks.firstIndex(where: { $0.id == sourceID }),
              let target = blocks.firstIndex(where: { $0.id == targetID }) else { return false }
        let block = blocks.remove(at: source)
        let adjustedTarget = source < target ? target - 1 : target
        blocks.insert(block, at: adjustedTarget)
        return true
    }

    private func openSlashMenu(for id: UUID) {
        slashTargetID = id
    }

    private func focus(_ id: UUID, unless condition: Bool) {
        guard !condition else { return }
        Task { @MainActor in
            await Task.yield()
            focusedBlockID = id
        }
    }

    private func persistChanges() {
        memo.setBlocks(blocks)
        memo.updatedAt = Date()
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            try? modelContext.save()
        }
    }

    private func deletePage() {
        saveTask?.cancel()
        modelContext.delete(memo)
        try? modelContext.save()
        dismiss()
    }

    private func iconName(_ icon: String) -> String {
        ["📄": "문서", "📝": "메모", "📚": "공부", "🎧": "듣기", "🧠": "암기", "💡": "아이디어", "✅": "체크", "📌": "중요", "🎯": "목표", "🔖": "북마크"][icon] ?? "아이콘"
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

private struct StudyPageBlockRow: View {
    @Binding var block: StudyPageBlock
    let number: Int
    let focusedBlockID: FocusState<UUID?>.Binding
    let onInsertAfter: (StudyPageBlockKind) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onTransform: (StudyPageBlockKind) -> Void
    let onMove: (Int) -> Void
    let onSlashCommand: () -> Void
    let onDropBlock: (UUID, UUID) -> Bool

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            blockHandle
                .opacity(isHovering || focusedBlockID.wrappedValue == block.id ? 1 : 0.28)

            blockContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(block.indentLevel) * 24)
        .padding(.vertical, block.kind.verticalPadding)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .draggable(block.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let sourceID = UUID(uuidString: value) else { return false }
            return onDropBlock(sourceID, block.id)
        }
        .onChange(of: block.text) { _, text in
            if text == "/" { onSlashCommand() }
        }
    }

    private var blockHandle: some View {
        HStack(spacing: 0) {
            Button { onInsertAfter(.text) } label: {
                Image(systemName: "plus")
                    .frame(width: 25, height: 28)
            }

            Menu {
                Menu("블록 전환") {
                    ForEach(StudyPageBlockKind.allCases) { kind in
                        Button { onTransform(kind) } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                    }
                }
                Button("위로 이동") { onMove(-1) }
                Button("아래로 이동") { onMove(1) }
                Button("들여쓰기") { block.indentLevel = min(3, block.indentLevel + 1) }
                    .disabled(block.indentLevel >= 3)
                Button("내어쓰기") { block.indentLevel = max(0, block.indentLevel - 1) }
                    .disabled(block.indentLevel == 0)
                Button("복제") { onDuplicate() }
                Divider()
                Button("삭제", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 25, height: 28)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .frame(width: 52)
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.kind {
        case .divider:
            Divider().padding(.vertical, 11)

        case .table:
            StudyPageTableEditor(block: $block)

        case .toDo:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { block.isChecked.toggle() } label: {
                    Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(block.isChecked ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                blockTextField
                    .strikethrough(block.isChecked, color: .secondary)
                    .foregroundStyle(block.isChecked ? .secondary : .primary)
            }

        case .toggle:
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Button { block.isExpanded.toggle() } label: {
                        Image(systemName: block.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                    blockTextField
                }
                if block.isExpanded {
                    TextField("토글 안의 내용을 입력하세요", text: $block.detail, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...12)
                        .padding(.leading, 24)
                        .foregroundStyle(.secondary)
                }
            }

        case .quote:
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Color.primary.opacity(0.72))
                    .frame(width: 3)
                blockTextField
                    .font(.body.italic())
            }

        case .callout:
            HStack(alignment: .top, spacing: 12) {
                Text("💡").font(.title3)
                blockTextField
            }
            .padding(14)
            .background(NotionStyle.calloutBackground, in: RoundedRectangle(cornerRadius: 5))

        case .code:
            TextEditor(text: $block.text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(12)
                .background(NotionStyle.codeBackground, in: RoundedRectangle(cornerRadius: 5))
                .focused(focusedBlockID, equals: block.id)

        default:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if block.kind == .bulletedList { Text("•").font(.title3) }
                if block.kind == .numberedList { Text("\(number).").frame(minWidth: 20, alignment: .trailing) }
                blockTextField
            }
        }
    }

    private var blockTextField: some View {
        TextField(block.kind.placeholder, text: $block.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(block.kind.font)
            .lineLimit(1...20)
            .focused(focusedBlockID, equals: block.id)
            .onSubmit { onInsertAfter(block.kind.continuationKind) }
    }
}

private struct StudyPageTableEditor: View {
    @Binding var block: StudyPageBlock

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(block.tableColumns.indices, id: \.self) { column in
                        TextField("열 \(column + 1)", text: columnBinding(column))
                            .font(.subheadline.weight(.semibold))
                            .textFieldStyle(.plain)
                            .padding(9)
                            .frame(width: 150)
                            .background(NotionStyle.tableHeaderBackground)
                            .overlay(Rectangle().stroke(NotionStyle.tableBorder, lineWidth: 0.5))
                    }
                }

                ForEach(block.tableRows.indices, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(block.tableColumns.indices, id: \.self) { column in
                            tableCell(row: row, column: column)
                        }
                    }
                }

                HStack(spacing: 16) {
                    Button { addRow() } label: { Label("행 추가", systemImage: "plus") }
                    Button { addColumn() } label: { Label("열 추가", systemImage: "plus") }
                    if block.tableRows.count > 1 {
                        Button("마지막 행 삭제", role: .destructive) { block.tableRows.removeLast() }
                    }
                    if block.tableColumns.count > 1 {
                        Button("마지막 열 삭제", role: .destructive) { removeLastColumn() }
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 9)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func columnBinding(_ column: Int) -> Binding<String> {
        Binding(get: { block.tableColumns[column] }, set: { block.tableColumns[column] = $0 })
    }

    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: {
                guard block.tableRows.indices.contains(row), block.tableRows[row].indices.contains(column) else { return "" }
                return block.tableRows[row][column]
            },
            set: { value in
                normalizeRows()
                block.tableRows[row][column] = value
            }
        )
    }

    private func tableCell(row: Int, column: Int) -> some View {
        let binding = cellBinding(row: row, column: column)
        return TextField("", text: binding, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .padding(9)
            .frame(width: 150, alignment: .topLeading)
            .frame(minHeight: 38, alignment: .topLeading)
            .overlay(Rectangle().stroke(NotionStyle.tableBorder, lineWidth: 0.5))
    }

    private func normalizeRows() {
        for index in block.tableRows.indices {
            while block.tableRows[index].count < block.tableColumns.count { block.tableRows[index].append("") }
        }
    }

    private func addRow() {
        block.tableRows.append(Array(repeating: "", count: block.tableColumns.count))
    }

    private func addColumn() {
        block.tableColumns.append("열 \(block.tableColumns.count + 1)")
        for index in block.tableRows.indices { block.tableRows[index].append("") }
    }

    private func removeLastColumn() {
        block.tableColumns.removeLast()
        for index in block.tableRows.indices where !block.tableRows[index].isEmpty {
            block.tableRows[index].removeLast()
        }
    }
}

private struct BlockCommandMenu: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    let onSelect: (StudyPageBlockKind) -> Void

    private var kinds: [StudyPageBlockKind] {
        guard !searchText.isEmpty else { return StudyPageBlockKind.allCases }
        return StudyPageBlockKind.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) || $0.helpText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(kinds) { kind in
                Button {
                    onSelect(kind)
                    dismiss()
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: kind.systemImage)
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .background(NotionStyle.hoverBackground, in: RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).foregroundStyle(.primary)
                            Text(kind.helpText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "블록 검색")
            .navigationTitle("블록 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private enum PageCoverStyle: String, CaseIterable, Identifiable {
    case none, sand, blue, green, rose, violet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "없음"
        case .sand: "샌드"
        case .blue: "블루"
        case .green: "그린"
        case .rose: "로즈"
        case .violet: "바이올렛"
        }
    }
}

private struct PageCover: View {
    let style: String
    var body: some View {
        Rectangle().fill(gradient)
    }

    private var gradient: LinearGradient {
        switch PageCoverStyle(rawValue: style) ?? .sand {
        case .none, .sand: LinearGradient(colors: [Color(red: 0.82, green: 0.75, blue: 0.64), Color(red: 0.56, green: 0.47, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .blue: LinearGradient(colors: [.blue.opacity(0.45), .indigo.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .green: LinearGradient(colors: [.mint.opacity(0.55), .green.opacity(0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .rose: LinearGradient(colors: [.pink.opacity(0.42), .red.opacity(0.52)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .violet: LinearGradient(colors: [.purple.opacity(0.42), .indigo.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private enum NotionStyle {
    static var pageBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    static var editorBackground: Color { pageBackground }
    static var hoverBackground: Color { Color.secondary.opacity(0.09) }
    static var calloutBackground: Color { Color.secondary.opacity(0.10) }
    static var codeBackground: Color { Color.secondary.opacity(0.09) }
    static var tableHeaderBackground: Color { Color.secondary.opacity(0.09) }
    static var tableBorder: Color { Color.secondary.opacity(0.28) }
}

private extension StudyPageBlockKind {
    var placeholder: String {
        switch self {
        case .heading1, .heading2, .heading3: "제목"
        case .bulletedList, .numberedList, .toDo: "목록"
        case .toggle: "토글"
        case .quote: "인용문"
        case .callout: "강조할 내용"
        default: "텍스트를 입력하거나 /를 입력하세요"
        }
    }

    var font: Font {
        switch self {
        case .heading1: .system(size: 30, weight: .bold)
        case .heading2: .system(size: 24, weight: .bold)
        case .heading3: .system(size: 20, weight: .semibold)
        default: .body
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .heading1: 12
        case .heading2: 9
        case .heading3: 7
        default: 3
        }
    }

    var continuationKind: StudyPageBlockKind {
        switch self {
        case .bulletedList, .numberedList, .toDo: self
        default: .text
        }
    }
}

private let pageIcons = ["📄", "📝", "📚", "🎧", "🧠", "💡", "✅", "📌", "🎯", "🔖"]

#Preview {
    NavigationStack { StudyMemosView() }
        .modelContainer(for: [StudyMemo.self], inMemory: true)
}
