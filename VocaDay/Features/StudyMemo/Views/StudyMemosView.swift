import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct StudyMemosView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyMemo.updatedAt, order: .reverse) private var memos: [StudyMemo]

    @StateObject private var viewModel = StudyMemosListViewModel()
    @Environment(\.appNavigate) private var navigate
    @State private var memoPendingDeletion: StudyMemo?

    private var sortedMemos: [StudyMemo] {
        memos.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        AppCollectionPage(
            maxContentWidth: 860,
            horizontalPadding: 14,
            verticalPadding: 12
        ) {
            if memos.isEmpty {
                emptyPagesView
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(sortedMemos) { memo in
                        NavigationLink(value: AppRoute.studyMemo(memoID: memo.id)) {
                            StudyPageListRow(presentation: StudyPageRowPresentation(memo: memo))
                                .componentSpotlight(.studyMemoCollection)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                viewModel.togglePin(memo, in: modelContext)
                            } label: {
                                Label(memo.isPinned ? "고정 해제" : "고정", systemImage: memo.isPinned ? "pin.slash" : "pin")
                            }

                            Button { duplicate(memo) } label: {
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
        }
        .background(StudyPageStyle.background)
        .navigationTitle("학습 메모")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button(action: createPage) {
                    AppToolbarActionLabel(title: "새 페이지", systemImage: "plus")
                }
                .componentSpotlight(.createStudyMemoButton)
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
            viewModel.repairLegacyData(memos, in: modelContext)
            viewModel.migrateLegacyPages(memos, in: modelContext)
        }
        .alert(item: $viewModel.errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private var emptyPagesView: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text("페이지가 없습니다")
                .font(.headline)
            Text("+를 눌러 첫 학습 페이지를 만드세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("새 페이지", action: createPage)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    private func createPage() {
        guard let memo = viewModel.createPage(in: modelContext) else { return }
        navigate(.studyMemo(memoID: memo.id))
    }

    private func duplicate(_ source: StudyMemo) {
        guard let copy = viewModel.duplicate(source, in: modelContext) else { return }
        navigate(.studyMemo(memoID: copy.id))
    }

    private func deletePendingMemo() {
        guard let memoPendingDeletion else { return }
        if viewModel.deletePendingMemo(memoPendingDeletion, in: modelContext) {
            self.memoPendingDeletion = nil
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

struct StudyPageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyPageCategory.createdAt) private var categories: [StudyPageCategory]
    @Bindable var memo: StudyMemo

    @State private var blocks: [StudyPageBlock]
    @State private var blockTexts: [UUID: AttributedString]
    @State private var blockSelections: [UUID: AttributedTextSelection] = [:]
    @State private var blockEditorRevisions: [UUID: Int] = [:]
    @State private var pendingEditorReplacements: [UUID: PendingEditorReplacement] = [:]
    @FocusState private var focusedBlockID: UUID?
    @State private var lastEditingBlockID: UUID?
    @State private var slashCommandBlockID: UUID?
    @State private var isChangingBlocksProgrammatically = false
    @State private var isHeaderScrolledAway = false
    @State private var showsCategoryPicker = false
    @State private var showsDeleteConfirmation = false
    @State private var showsBlockPicker = false
    @State private var showsCustomHighlightPicker = false
    @State private var customHighlightColor = Color.yellow
    @State private var saveTask: Task<Void, Never>?
    @State private var markdownDocument = StudyMarkdownDocument()
    @State private var isImportingMarkdown = false
    @State private var isExportingMarkdown = false
    @State private var pendingMarkdownPage: ImportedMarkdownPage?
    @State private var showsMarkdownImportOptions = false
    @State private var markdownStatusMessage: String?
    @State private var errorAlert: VocaAlert?

    init(memo: StudyMemo) {
        self.memo = memo
        let initialBlocks = StudyNotionCodec.blocks(for: memo)
        _blocks = State(initialValue: initialBlocks)
        _blockTexts = State(initialValue: Dictionary(uniqueKeysWithValues: initialBlocks.map {
            let text = StudyNotionCodec.attributedText(for: $0)
            return ($0.id, StudyEditorBuffer.displayText(text, for: $0.kind))
        }))
    }

    var body: some View {
        editorWithMarkdownTransfer
            .onChange(of: memo.title) { _, _ in persistMetadata() }
            .onChange(of: memo.categoryID) { _, _ in persistMetadata() }
            .onDisappear {
                saveTask?.cancel()
                saveImmediately()
            }
            .alert(item: $errorAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message))
            }
    }

    private var editorLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("제목 없음", text: $memo.title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 38, weight: .bold))
                    .lineLimit(1...3)

                Button {
                    showsCategoryPicker = true
                } label: {
                    if memo.categoryName.isEmpty {
                        Label("분류 지정", systemImage: "tag")
                            .foregroundStyle(.secondary)
                    } else {
                        StudyCategoryBadge(name: memo.categoryName, colorRawValue: memo.categoryColor)
                    }
                }
                .buttonStyle(.plain)

            }
            .padding(.horizontal, editorHorizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 14)
            .frame(maxWidth: editorMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(blocks.indices, id: \.self) { index in
                    notionBlock(at: index)
                }

                Color.clear
                    .frame(height: 160)
                    .contentShape(Rectangle())
                    .onTapGesture { focusTrailingBlock() }
            }
            .padding(.horizontal, editorHorizontalPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: editorMaxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 72
        } action: { _, isScrolledAway in
            isHeaderScrolledAway = isScrolledAway
        }
        .background(StudyPageStyle.background)
        .navigationTitle(isHeaderScrolledAway ? memo.title : "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Button {
                    memo.isPinned.toggle()
                    persistMetadata()
                } label: {
                    Image(systemName: memo.isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(memo.isPinned ? "고정 해제" : "페이지 고정")

                Menu {
                    Button {
                        isImportingMarkdown = true
                    } label: {
                        Label("MD 파일 가져오기", systemImage: "doc.badge.plus")
                    }
                    Button {
                        prepareMarkdownExport()
                    } label: {
                        Label("MD 파일로 내보내기", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button("페이지 삭제", role: .destructive) { showsDeleteConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("페이지 메뉴")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StudyInlineFormattingBar(
                activeCommands: activeInlineCommands,
                activeBlockKind: activeBlockKind,
                onAddBlock: {
                    rememberFocusedBlock()
                    showsBlockPicker = true
                },
                onCommand: applyInline,
                onToggleBlockKind: toggleBlockKind,
                onHighlight: applyHighlight,
                onCustomHighlight: {
                    rememberFocusedBlock()
                    showsCustomHighlightPicker = true
                },
                onDismissKeyboard: { focusedBlockID = nil }
            )
        }
    }

    @ViewBuilder
    private func notionBlock(at index: Int) -> some View {
        let block = blocks[index]
        HStack(alignment: block.kind == .divider ? .center : .top, spacing: 5) {
            #if os(macOS)
            blockHandle(for: block, at: index)
            #endif

            switch block.kind {
            case .divider:
                Divider()
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
                    .onTapGesture { insertBlock(after: index) }
            case .toDo:
                Button {
                    let binding = checkedBinding(for: block.id)
                    binding.wrappedValue.toggle()
                } label: {
                    Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                        .font(.body)
                        .foregroundStyle(block.isChecked ? Color.accentColor : .secondary)
                }
                    .buttonStyle(.plain)
                    .padding(.top, 7)
                    .accessibilityLabel(block.isChecked ? "완료 취소" : "완료로 표시")
                blockTextEditor(block: block, font: .body, placeholder: "할 일을 입력하세요")
            case .bulletedList:
                Text("•")
                    .font(.body.weight(.semibold))
                    .frame(width: 18)
                    .padding(.top, 7)
                blockTextEditor(block: block, font: .body, placeholder: "목록")
            case .numberedList:
                Text("\(numberedOrdinal(at: index)).")
                    .font(.body)
                    .frame(minWidth: 22, alignment: .trailing)
                    .padding(.top, 7)
                blockTextEditor(block: block, font: .body, placeholder: "목록")
            case .quote:
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.65))
                    .frame(width: 3)
                    .padding(.vertical, 4)
                blockTextEditor(block: block, font: .body, placeholder: "인용문")
            case .callout:
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .padding(.top, 8)
                blockTextEditor(block: block, font: .body, placeholder: "메모")
                    .padding(.horizontal, 8)
                    .background(Color.yellow.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
            case .code:
                blockTextEditor(block: block, font: .system(.body, design: .monospaced), placeholder: "코드를 입력하세요")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            case .heading1:
                blockTextEditor(block: block, font: .system(size: 30, weight: .bold), placeholder: "제목 1")
            case .heading2:
                blockTextEditor(block: block, font: .system(size: 24, weight: .bold), placeholder: "제목 2")
            case .heading3:
                blockTextEditor(block: block, font: .system(size: 20, weight: .semibold), placeholder: "제목 3")
            case .table:
                blockTextEditor(block: block, font: .system(.body, design: .monospaced), placeholder: "표 내용")
            case .toggle, .text:
                blockTextEditor(block: block, font: .body, placeholder: index == 0 ? "내용을 입력하거나 /를 눌러 블록을 선택하세요" : "내용을 입력하세요")
            }
        }
        .padding(.vertical, block.kind == .heading1 ? 6 : 1)
        .animation(.snappy(duration: 0.18), value: block.kind)
    }

    private func blockTextEditor(block: StudyPageBlock, font: Font, placeholder: String) -> some View {
        let editorRevision = blockEditorRevisions[block.id] ?? 0
        return ZStack(alignment: .topLeading) {
            if shouldShowPlaceholder(for: block.id) {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
            }

            TextEditor(
                text: textBinding(for: block.id, revision: editorRevision),
                selection: selectionBinding(for: block.id, revision: editorRevision)
            )
                .id("\(block.id.uuidString)-\(block.kind.rawValue)-\(editorRevision)")
                .font(font)
                .lineSpacing(6)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: block.kind == .code ? 76 : 36, alignment: .top)
                .focused($focusedBlockID, equals: block.id)
                .onChange(of: focusedBlockID) { _, newValue in
                    if newValue == block.id {
                        lastEditingBlockID = block.id
                        slashCommandBlockID = slashCommandID(for: block.id)
                        if StudyEditorBuffer.isOnlyDeletionSentinel(blockTexts[block.id]) {
                            Task { @MainActor in
                                // TextEditor applies its own tap selection after focus changes.
                                // Move behind the sentinel after that native update completes.
                                try? await Task.sleep(for: .milliseconds(50))
                                guard focusedBlockID == block.id,
                                      let editorText = blockTexts[block.id],
                                      StudyEditorBuffer.isOnlyDeletionSentinel(editorText)
                                else { return }
                                blockSelections[block.id] = AttributedTextSelection(
                                    insertionPoint: editorText.endIndex
                                )
                            }
                        }
                    }
                }
        }
        .popover(isPresented: slashCommandBinding(for: block.id), arrowEdge: .bottom) {
            StudySlashCommandMenu(query: slashQuery(for: block.id)) { command in
                applySlashCommand(command, to: block.id)
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private func blockHandle(for block: StudyPageBlock, at index: Int) -> some View {
        Menu {
            Button("아래에 블록 추가", systemImage: "plus", action: { insertBlock(after: index) })
            Button("복제", systemImage: "plus.square.on.square", action: { duplicateBlock(at: index) })
            Divider()
            Button("삭제", systemImage: "trash", role: .destructive, action: { deleteBlock(at: index) })
        } label: {
            Image(systemName: "circle.grid.2x3.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 34)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("블록 메뉴")
        .opacity(focusedBlockID == block.id ? 1 : 0.35)
    }

    private var editorWithDialogs: some View {
        editorLayout
            .sheet(isPresented: $showsCategoryPicker) {
                StudyCategoryPicker(memo: memo)
            }
            .sheet(isPresented: $showsBlockPicker) {
                StudyBlockPickerSheet { command in
                    insertBlockFromToolbar(command)
                }
                #if os(macOS)
                .frame(width: 460, height: 600)
                .presentationSizing(.page)
                #endif
            }
            .sheet(isPresented: $showsCustomHighlightPicker) {
                NavigationStack {
                    Form {
                        ColorPicker("하이라이트 색상", selection: $customHighlightColor, supportsOpacity: true)
                        Button("선택한 글자에 적용") {
                            applyHighlight(customHighlightColor)
                            showsCustomHighlightPicker = false
                        }
                        .disabled(activeEditingBlockID == nil)
                    }
                    .formStyle(.grouped)
                    .navigationTitle("사용자 지정 색상")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("닫기") { showsCustomHighlightPicker = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .confirmationDialog("이 페이지를 삭제할까요?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("삭제", role: .destructive, action: deletePage)
                Button("취소", role: .cancel) {}
            } message: {
                Text("삭제한 페이지는 복구할 수 없습니다.")
            }
    }

    private var editorWithMarkdownTransfer: some View {
        editorWithDialogs
            .confirmationDialog("Markdown 내용을 어떻게 가져올까요?", isPresented: $showsMarkdownImportOptions, titleVisibility: .visible) {
                Button("현재 내용 뒤에 추가") { applyPendingMarkdown(replacing: false) }
                Button("현재 내용 교체", role: .destructive) { applyPendingMarkdown(replacing: true) }
                Button("취소", role: .cancel) { pendingMarkdownPage = nil }
            } message: {
                Text("교체하면 파일의 첫 번째 제목과 VocaDay 분류 정보도 현재 페이지에 적용됩니다.")
            }
            .fileImporter(
                isPresented: $isImportingMarkdown,
                allowedContentTypes: [.markdownDocument, .plainText],
                allowsMultipleSelection: false,
                onCompletion: importMarkdown
            )
            .fileExporter(
                isPresented: $isExportingMarkdown,
                document: markdownDocument,
                contentType: .markdownDocument,
                defaultFilename: markdownFilename,
                onCompletion: finishMarkdownExport
            )
            .alert(
                "Markdown 파일",
                isPresented: Binding(
                    get: { markdownStatusMessage != nil },
                    set: { if !$0 { markdownStatusMessage = nil } }
                )
            ) {
                Button("확인") { markdownStatusMessage = nil }
            } message: {
                Text(markdownStatusMessage ?? "")
            }
    }

    private func applyInline(_ command: StudyInlineCommand) {
        guard
            let id = activeEditingBlockID,
            let text = blockTexts[id]
        else { return }

        let selection = blockSelections[id] ?? AttributedTextSelection(insertionPoint: text.endIndex)
        let shouldEnable = !isInlineCommandActive(command, selection: selection, in: text)

        transformSelection(in: id) { attributes in
            switch command {
            case .bold:
                updatePresentationIntent(
                    .stronglyEmphasized,
                    isEnabled: shouldEnable,
                    attributes: &attributes
                )
                updateInlineFont(in: &attributes, blockID: id)
            case .italic:
                updatePresentationIntent(
                    .emphasized,
                    isEnabled: shouldEnable,
                    attributes: &attributes
                )
                updateInlineFont(in: &attributes, blockID: id)
            case .underline:
                attributes.underlineStyle = shouldEnable ? .single : nil
            case .strikethrough:
                attributes.strikethroughStyle = shouldEnable ? .single : nil
            }
        }
    }

    private var activeInlineCommands: Set<StudyInlineCommand> {
        guard
            let id = activeEditingBlockID,
            let text = blockTexts[id]
        else { return [] }

        let selection = blockSelections[id] ?? AttributedTextSelection(insertionPoint: text.endIndex)
        return Set(StudyInlineCommand.allCases.filter {
            isInlineCommandActive($0, selection: selection, in: text)
        })
    }

    private func isInlineCommandActive(
        _ command: StudyInlineCommand,
        selection: AttributedTextSelection,
        in text: AttributedString
    ) -> Bool {
        switch selection.indices(in: text) {
        case .insertionPoint:
            return isInlineCommandActive(command, attributes: selection.typingAttributes(in: text))
        case .ranges:
            let attributes = Array(selection.attributes(in: text))
            return !attributes.isEmpty && attributes.allSatisfy {
                isInlineCommandActive(command, attributes: $0)
            }
        }
    }

    private func isInlineCommandActive(
        _ command: StudyInlineCommand,
        attributes: AttributeContainer
    ) -> Bool {
        switch command {
        case .bold:
            attributes.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        case .italic:
            attributes.inlinePresentationIntent?.contains(.emphasized) == true
        case .underline:
            attributes.underlineStyle != nil
        case .strikethrough:
            attributes.strikethroughStyle != nil
        }
    }

    private func updatePresentationIntent(
        _ intent: InlinePresentationIntent,
        isEnabled: Bool,
        attributes: inout AttributeContainer
    ) {
        var intents = attributes.inlinePresentationIntent ?? []
        if isEnabled {
            intents.insert(intent)
        } else {
            intents.remove(intent)
        }
        attributes.inlinePresentationIntent = intents.isEmpty ? nil : intents
    }

    private func updateInlineFont(in attributes: inout AttributeContainer, blockID: UUID) {
        let intents = attributes.inlinePresentationIntent ?? []
        var font = blockFont(for: blockID)
        if intents.contains(.stronglyEmphasized) {
            font = font.bold()
        }
        if intents.contains(.emphasized) {
            font = font.italic()
        }
        attributes.font = font
    }

    private func applyHighlight(_ color: Color?) {
        guard let id = activeEditingBlockID else { return }
        transformSelection(in: id) { $0.backgroundColor = color }
    }

    private func transformSelection(in id: UUID, _ body: (inout AttributeContainer) -> Void) {
        guard var text = blockTexts[id] else { return }
        var selection = blockSelections[id] ?? AttributedTextSelection(insertionPoint: text.endIndex)
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            var attributes = selection.typingAttributes(in: text)
            body(&attributes)
            selection = AttributedTextSelection(insertionPoint: index, typingAttributes: attributes)
        case .ranges:
            text.transformAttributes(in: &selection, body: body)
        }
        blockTexts[id] = text
        blockSelections[id] = selection
        updateStoredText(for: id)
        persistChanges()
    }

    private func textBinding(for id: UUID, revision: Int) -> Binding<AttributedString> {
        Binding(
            get: { blockTexts[id] ?? AttributedString() },
            set: { newValue in
                guard blockEditorRevisions[id, default: 0] == revision else { return }
                handleTextChange(newValue, for: id)
            }
        )
    }

    private func selectionBinding(for id: UUID, revision: Int) -> Binding<AttributedTextSelection> {
        Binding(
            get: { blockSelections[id] ?? AttributedTextSelection() },
            set: {
                guard blockEditorRevisions[id, default: 0] == revision else { return }
                blockSelections[id] = $0
                lastEditingBlockID = id
            }
        )
    }

    private func checkedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { blocks.first(where: { $0.id == id })?.isChecked ?? false },
            set: { value in
                guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
                blocks[index].isChecked = value
                persistChanges()
            }
        )
    }

    private func handleTextChange(_ newValue: AttributedString, for id: UUID) {
        lastEditingBlockID = id
        guard let currentIndex = blocks.firstIndex(where: { $0.id == id }) else { return }

        let incomingPlainText = String(StudyEditorBuffer.logicalText(newValue).characters)
        if let pending = pendingEditorReplacements[id] {
            if incomingPlainText == pending.staleText, pending.staleText != pending.expectedText {
                return
            }
            pendingEditorReplacements[id] = nil
        }

        if !isChangingBlocksProgrammatically,
           StudyEditorBuffer.usesDeletionSentinel(for: blocks[currentIndex].kind),
           plainText(for: id).isEmpty,
           newValue.characters.isEmpty {
            removeListFormattingFromEmptyBlock(at: currentIndex)
            return
        }

        let logicalValue = StudyEditorBuffer.logicalText(newValue)
        let removedDeletionSentinel = logicalValue.characters.count != newValue.characters.count
        if !isChangingBlocksProgrammatically,
           applyMarkdownBlockShortcutIfNeeded(logicalValue, to: id) {
            return
        }
        blockTexts[id] = logicalValue
        if removedDeletionSentinel {
            reloadEditor(for: id, replacing: newValue, with: logicalValue)
        }
        updateStoredText(for: id)
        slashCommandBlockID = slashCommandID(for: id)
        guard !isChangingBlocksProgrammatically,
              blocks[currentIndex].kind != .code,
              let newline = logicalValue.characters.firstIndex(of: "\n") else {
            persistChanges()
            if removedDeletionSentinel {
                restoreFocus(to: id)
            }
            return
        }
        splitBlock(at: currentIndex, text: logicalValue, newline: newline)
    }

    private func splitBlock(at index: Int, text: AttributedString, newline: AttributedString.Index) {
        guard !isChangingBlocksProgrammatically else { return }
        isChangingBlocksProgrammatically = true
        Task { @MainActor in
            await Task.yield()
            splitBlockImmediately(at: index, text: text, newline: newline)
        }
    }

    private func splitBlockImmediately(at index: Int, text: AttributedString, newline: AttributedString.Index) {
        guard blocks.indices.contains(index) else {
            isChangingBlocksProgrammatically = false
            return
        }
        let current = blocks[index]
        let afterStart = text.characters.index(after: newline)
        let before = AttributedString(text[..<newline])
        let after = AttributedString(text[afterStart...])

        if before.characters.isEmpty && [.bulletedList, .numberedList, .toDo, .quote].contains(current.kind) {
            blocks[index].kind = .text
            blockTexts[current.id] = after
            blockSelections[current.id] = AttributedTextSelection(insertionPoint: after.startIndex)
            reloadEditor(for: current.id, replacing: text, with: after)
            isChangingBlocksProgrammatically = false
            updateStoredText(for: current.id)
            persistChanges()
            restoreFocus(to: current.id)
            return
        }

        blockTexts[current.id] = before
        reloadEditor(for: current.id, replacing: text, with: before)
        updateStoredText(for: current.id)
        let nextKind: StudyPageBlockKind = [.bulletedList, .numberedList, .toDo].contains(current.kind) ? current.kind : .text
        var next = StudyPageBlock(kind: nextKind, text: String(after.characters))
        next.richTextData = StudyNotionCodec.encode(after)
        blocks.insert(next, at: index + 1)
        let nextEditorText = StudyEditorBuffer.displayText(after, for: nextKind)
        blockTexts[next.id] = nextEditorText
        isChangingBlocksProgrammatically = false
        persistChanges()

        Task { @MainActor in
            await Task.yield()
            focusedBlockID = next.id
            let insertionPoint = StudyEditorBuffer.isOnlyDeletionSentinel(nextEditorText)
                ? nextEditorText.endIndex
                : nextEditorText.startIndex
            blockSelections[next.id] = AttributedTextSelection(insertionPoint: insertionPoint)
        }
    }

    private func applySlashCommand(_ command: StudySlashCommand, to id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let previousEditorText = blockTexts[id] ?? AttributedString()
        isChangingBlocksProgrammatically = true
        blocks[index].kind = command.kind
        let empty = StudyEditorBuffer.displayText(AttributedString(), for: command.kind)
        blockTexts[id] = empty
        blockSelections[id] = AttributedTextSelection(insertionPoint: empty.endIndex)
        reloadEditor(for: id, replacing: previousEditorText, with: empty)
        slashCommandBlockID = nil
        updateStoredText(for: id)

        if command.kind == .divider {
            let next = StudyPageBlock()
            blocks.insert(next, at: index + 1)
            blockTexts[next.id] = AttributedString()
            isChangingBlocksProgrammatically = false
            persistChanges()
            Task { @MainActor in
                await Task.yield()
                focusedBlockID = next.id
            }
        } else {
            isChangingBlocksProgrammatically = false
            persistChanges()
            Task { @MainActor in
                await Task.yield()
                focusedBlockID = id
                guard let text = blockTexts[id] else { return }
                blockSelections[id] = AttributedTextSelection(insertionPoint: text.endIndex)
            }
        }
    }

    private func insertBlock(after index: Int) {
        let block = StudyPageBlock()
        blocks.insert(block, at: min(index + 1, blocks.count))
        blockTexts[block.id] = AttributedString()
        persistChanges()
        Task { @MainActor in
            await Task.yield()
            focusedBlockID = block.id
        }
    }

    private func duplicateBlock(at index: Int) {
        var copy = blocks[index]
        copy.id = UUID()
        blocks.insert(copy, at: index + 1)
        blockTexts[copy.id] = blockTexts[blocks[index].id] ?? AttributedString(copy.text)
        persistChanges()
    }

    private func deleteBlock(at index: Int) {
        let removed = blocks.remove(at: index)
        blockTexts[removed.id] = nil
        blockSelections[removed.id] = nil
        blockEditorRevisions[removed.id] = nil
        if blocks.isEmpty {
            let block = StudyPageBlock()
            blocks = [block]
            blockTexts[block.id] = AttributedString()
        }
        let target = blocks[min(index, blocks.count - 1)].id
        persistChanges()
        focusedBlockID = target
    }

    private func focusTrailingBlock() {
        if let last = blocks.last, last.kind == .text, plainText(for: last.id).isEmpty {
            focusedBlockID = last.id
        } else {
            insertBlock(after: blocks.count - 1)
        }
    }

    private func updateStoredText(for id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }), let text = blockTexts[id] else { return }
        let logicalText = StudyEditorBuffer.logicalText(text)
        blocks[index].text = String(logicalText.characters)
        blocks[index].richTextData = StudyNotionCodec.encode(logicalText)
    }

    private func plainText(for id: UUID) -> String {
        guard let text = blockTexts[id] else { return "" }
        return String(StudyEditorBuffer.logicalText(text).characters)
    }

    private func shouldShowPlaceholder(for id: UUID) -> Bool {
        guard plainText(for: id).isEmpty else { return false }
        if focusedBlockID == id { return true }
        return blocks.count == 1 && lastEditingBlockID == nil
    }

    private var activeEditingBlockID: UUID? {
        focusedBlockID ?? lastEditingBlockID
    }

    private var activeBlockKind: StudyPageBlockKind? {
        guard let id = activeEditingBlockID else { return nil }
        return blocks.first(where: { $0.id == id })?.kind
    }

    private func rememberFocusedBlock() {
        if let focusedBlockID {
            lastEditingBlockID = focusedBlockID
        }
    }

    private func applyMarkdownBlockShortcutIfNeeded(_ text: AttributedString, to id: UUID) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == id }),
              blocks[index].kind == .text,
              let conversion = StudyMarkdownBlockShortcut.conversion(for: text) else {
            return false
        }

        isChangingBlocksProgrammatically = true
        Task { @MainActor in
            await Task.yield()
            guard blocks.indices.contains(index), blocks[index].id == id else {
                isChangingBlocksProgrammatically = false
                return
            }
            blocks[index].kind = conversion.kind
            let editorRemainder = StudyEditorBuffer.displayText(conversion.remainder, for: conversion.kind)
            blockTexts[id] = editorRemainder
            blockSelections[id] = AttributedTextSelection(insertionPoint: editorRemainder.endIndex)
            reloadEditor(for: id, replacing: text, with: editorRemainder)
            slashCommandBlockID = nil
            updateStoredText(for: id)
            isChangingBlocksProgrammatically = false

            if conversion.kind == .divider {
                let next = StudyPageBlock()
                blocks.insert(next, at: index + 1)
                blockTexts[next.id] = AttributedString()
                persistChanges()
                await Task.yield()
                focusedBlockID = next.id
            } else if conversion.kind != .code,
                      let newline = conversion.remainder.characters.firstIndex(of: "\n") {
                splitBlock(at: index, text: conversion.remainder, newline: newline)
            } else {
                persistChanges()
                await Task.yield()
                focusedBlockID = id
                blockSelections[id] = AttributedTextSelection(
                    insertionPoint: editorRemainder.endIndex
                )
            }
        }
        return true
    }

    private func toggleBlockKind(_ kind: StudyPageBlockKind) {
        guard
            let id = activeEditingBlockID,
            let index = blocks.firstIndex(where: { $0.id == id })
        else { return }

        isChangingBlocksProgrammatically = true
        blocks[index].kind = blocks[index].kind == kind ? .text : kind
        if blocks[index].kind != .toDo {
            blocks[index].isChecked = false
        }
        let logicalText = StudyEditorBuffer.logicalText(blockTexts[id] ?? AttributedString())
        let editorText = StudyEditorBuffer.displayText(logicalText, for: blocks[index].kind)
        blockTexts[id] = editorText
        blockSelections[id] = AttributedTextSelection(insertionPoint: editorText.endIndex)
        reloadEditor(for: id)
        updateStoredText(for: id)
        isChangingBlocksProgrammatically = false
        persistChanges()

        Task { @MainActor in
            await Task.yield()
            focusedBlockID = id
        }
    }

    private func removeListFormattingFromEmptyBlock(at index: Int) {
        let id = blocks[index].id
        let previousEditorText = blockTexts[id] ?? AttributedString()
        isChangingBlocksProgrammatically = true
        blocks[index].kind = .text
        let empty = AttributedString()
        blockTexts[id] = empty
        blockSelections[id] = AttributedTextSelection(insertionPoint: empty.startIndex)
        reloadEditor(for: id, replacing: previousEditorText, with: empty)
        updateStoredText(for: id)
        isChangingBlocksProgrammatically = false
        persistChanges()
        restoreFocus(to: id)
    }

    private func restoreFocus(to id: UUID) {
        Task { @MainActor in
            await Task.yield()
            focusedBlockID = id
            guard let text = blockTexts[id] else { return }
            blockSelections[id] = AttributedTextSelection(insertionPoint: text.endIndex)
        }
    }

    private func reloadEditor(
        for id: UUID,
        replacing staleText: AttributedString? = nil,
        with expectedText: AttributedString? = nil
    ) {
        if let staleText, let expectedText {
            let stale = String(StudyEditorBuffer.logicalText(staleText).characters)
            let expected = String(StudyEditorBuffer.logicalText(expectedText).characters)
            if stale != expected {
                pendingEditorReplacements[id] = PendingEditorReplacement(
                    staleText: stale,
                    expectedText: expected
                )
            }
        }
        if focusedBlockID == id {
            focusedBlockID = nil
        }
        blockEditorRevisions[id, default: 0] += 1
    }

    private func insertBlockFromToolbar(_ command: StudySlashCommand) {
        let targetIndex = activeEditingBlockID.flatMap { id in blocks.firstIndex(where: { $0.id == id }) }
            ?? max(blocks.count - 1, 0)

        if blocks.indices.contains(targetIndex), plainText(for: blocks[targetIndex].id).isEmpty {
            applySlashCommand(command, to: blocks[targetIndex].id)
            return
        }

        let block = StudyPageBlock()
        blocks.insert(block, at: min(targetIndex + 1, blocks.count))
        blockTexts[block.id] = AttributedString()
        applySlashCommand(command, to: block.id)
    }

    private func slashCommandID(for id: UUID) -> UUID? {
        let text = plainText(for: id)
        return text.hasPrefix("/") && !text.contains("\n") ? id : nil
    }

    private func slashQuery(for id: UUID) -> String {
        String(plainText(for: id).dropFirst())
    }

    private func slashCommandBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { slashCommandBlockID == id },
            set: { if !$0 { slashCommandBlockID = nil } }
        )
    }

    private func numberedOrdinal(at index: Int) -> Int {
        var ordinal = 1
        guard index > 0 else { return ordinal }
        for previous in stride(from: index - 1, through: 0, by: -1) {
            guard blocks[previous].kind == .numberedList else { break }
            ordinal += 1
        }
        return ordinal
    }

    private func blockFont(for id: UUID) -> Font {
        guard let kind = blocks.first(where: { $0.id == id })?.kind else { return .body }
        switch kind {
        case .heading1: return .system(size: 30, weight: .bold)
        case .heading2: return .system(size: 24, weight: .bold)
        case .heading3: return .system(size: 20, weight: .semibold)
        case .code, .table: return .system(.body, design: .monospaced)
        default: return .body
        }
    }

    private func persistChanges() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            saveImmediately()
        }
    }

    private func persistMetadata() {
        memo.updatedAt = Date()
        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
        }
    }

    private func saveImmediately() {
        for block in blocks { updateStoredText(for: block.id) }
        memo.setBlocks(blocks)
        var logicalTexts: [UUID: AttributedString] = [:]
        for (id, text) in blockTexts {
            logicalTexts[id] = StudyEditorBuffer.logicalText(text)
        }
        memo.plainTextContent = StudyNotionCodec.markdown(from: blocks, texts: logicalTexts)
        memo.richTextData = ""
        memo.updatedAt = Date()
        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
        }
    }

    private func importMarkdown(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            guard data.count <= 5 * 1_024 * 1_024,
                  let markdown = String(data: data, encoding: .utf8) else {
                throw StudyMarkdownError.invalidFile
            }

            pendingMarkdownPage = StudyMarkdownCodec.importPage(markdown)
            showsMarkdownImportOptions = true
        } catch {
            if !isUserCancellation(error) {
                markdownStatusMessage = "파일을 가져오지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    private func applyPendingMarkdown(replacing: Bool) {
        guard let page = pendingMarkdownPage else { return }

        if replacing {
            let imported = StudyNotionCodec.blocks(from: page.body)
            blocks = imported
            blockTexts = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, StudyNotionCodec.attributedText(for: $0)) })
            if !page.title.isEmpty { memo.title = page.title }
            if !page.categoryName.isEmpty { assignImportedCategory(named: page.categoryName) }
        } else {
            let imported = StudyNotionCodec.blocks(from: page.body)
            if blocks.count == 1, let only = blocks.first, only.kind == .text, plainText(for: only.id).isEmpty {
                blocks.removeAll()
                blockTexts.removeAll()
            }
            blocks.append(contentsOf: imported)
            for block in imported { blockTexts[block.id] = StudyNotionCodec.attributedText(for: block) }
        }

        pendingMarkdownPage = nil
        saveImmediately()
        markdownStatusMessage = replacing ? "Markdown 내용으로 페이지를 교체했습니다." : "Markdown 내용을 페이지 아래에 추가했습니다."
    }

    private func assignImportedCategory(named name: String) {
        if let category = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            memo.categoryID = category.id.uuidString
            memo.categoryName = category.name
            memo.categoryColor = category.colorRawValue
        } else {
            let category = StudyPageCategory(name: name, colorRawValue: StudyCategoryColor.gray.rawValue)
            modelContext.insert(category)
            memo.categoryID = category.id.uuidString
            memo.categoryName = category.name
            memo.categoryColor = category.colorRawValue
        }
    }

    private func prepareMarkdownExport() {
        var logicalTexts: [UUID: AttributedString] = [:]
        for (id, text) in blockTexts {
            logicalTexts[id] = StudyEditorBuffer.logicalText(text)
        }
        markdownDocument = StudyMarkdownDocument(
            markdown: StudyMarkdownCodec.exportPage(
                title: memo.title,
                categoryName: memo.categoryName,
                body: StudyNotionCodec.markdown(from: blocks, texts: logicalTexts)
            )
        )
        isExportingMarkdown = true
    }

    private func finishMarkdownExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            markdownStatusMessage = "Markdown 파일을 저장했습니다."
        case .failure(let error):
            if !isUserCancellation(error) {
                markdownStatusMessage = "파일을 저장하지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private var markdownFilename: String {
        let title = memo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = (title.isEmpty ? "VocaDay 학습 메모" : title)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return safe.hasSuffix(".md") ? safe : "\(safe).md"
    }

    private func deletePage() {
        modelContext.delete(memo)
        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
            return
        }
        dismiss()
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    private var editorHorizontalPadding: CGFloat {
        #if os(iOS)
        14
        #else
        28
        #endif
    }

    private var editorMaxWidth: CGFloat {
        #if os(iOS)
        .infinity
        #else
        1_080
        #endif
    }
}

private struct PendingEditorReplacement {
    let staleText: String
    let expectedText: String
}

enum StudyMarkdownBlockShortcut {
    struct Conversion {
        let kind: StudyPageBlockKind
        let remainder: AttributedString
    }

    private static let prefixes: [(String, StudyPageBlockKind)] = [
        ("### ", .heading3),
        ("## ", .heading2),
        ("# ", .heading1),
        ("[ ] ", .toDo),
        ("[] ", .toDo),
        ("1. ", .numberedList),
        ("\" ", .quote),
        ("- ", .bulletedList),
        ("* ", .bulletedList),
        ("+ ", .bulletedList)
    ]

    static func conversion(for text: AttributedString) -> Conversion? {
        let plain = String(text.characters)
        if plain == "---" {
            return Conversion(kind: .divider, remainder: AttributedString())
        }

        guard let (prefix, kind) = prefixes.first(where: { plain.hasPrefix($0.0) }) else {
            return nil
        }
        return Conversion(kind: kind, remainder: AttributedString(String(plain.dropFirst(prefix.count))))
    }
}

enum StudyEditorBuffer {
    // TextEditor ignores Backspace on an empty value. A non-breaking space behaves
    // like a real, invisible-to-the-model character, so one Backspace can be used
    // to leave an empty list/quote block just like Notion.
    private static let deletionSentinel: Character = "\u{00A0}"

    static func usesDeletionSentinel(for kind: StudyPageBlockKind) -> Bool {
        [.bulletedList, .numberedList, .toDo, .quote].contains(kind)
    }

    static func displayText(
        _ logicalText: AttributedString,
        for kind: StudyPageBlockKind
    ) -> AttributedString {
        guard usesDeletionSentinel(for: kind), logicalText.characters.isEmpty else {
            return logicalText
        }
        return AttributedString(String(deletionSentinel))
    }

    static func logicalText(_ editorText: AttributedString) -> AttributedString {
        var result = editorText
        while let sentinelIndex = result.characters.firstIndex(of: deletionSentinel) {
            let endIndex = result.characters.index(after: sentinelIndex)
            result.replaceSubrange(sentinelIndex..<endIndex, with: AttributedString())
        }
        return result
    }

    static func isOnlyDeletionSentinel(_ text: AttributedString?) -> Bool {
        guard let text else { return false }
        return text.characters.count == 1 && text.characters.first == deletionSentinel
    }
}

private enum StudyInlineCommand: String, CaseIterable, Identifiable {
    case bold, italic, underline, strikethrough
    var id: String { rawValue }
}

private struct StudyInlineFormattingBar: View {
    let activeCommands: Set<StudyInlineCommand>
    let activeBlockKind: StudyPageBlockKind?
    let onAddBlock: () -> Void
    let onCommand: (StudyInlineCommand) -> Void
    let onToggleBlockKind: (StudyPageBlockKind) -> Void
    let onHighlight: (Color?) -> Void
    let onCustomHighlight: () -> Void
    let onDismissKeyboard: () -> Void

    @State private var showsHighlightPalette = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    Button(action: onAddBlock) {
                        formatLabel("plus", title: "추가")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("블록 추가")

                    blockFormatButton("list.bullet", title: "글머리", kind: .bulletedList)
                    blockFormatButton("list.number", title: "번호", kind: .numberedList)

                    formatButton("bold", title: "굵게", command: .bold)
                    formatButton("italic", title: "기울임", command: .italic)
                    formatButton("underline", title: "밑줄", command: .underline)
                    formatButton("strikethrough", title: "취소선", command: .strikethrough)

                    Button { showsHighlightPalette = true } label: {
                        formatLabel("highlighter", title: "색")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("하이라이트 색상")
                    .popover(isPresented: $showsHighlightPalette, arrowEdge: .bottom) {
                        StudyHighlightPalette(
                            onSelect: { color in
                                showsHighlightPalette = false
                                onHighlight(color)
                            },
                            onCustom: {
                                showsHighlightPalette = false
                                onCustomHighlight()
                            }
                        )
                        .presentationCompactAdaptation(.popover)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
            .scrollIndicators(.hidden)

            Divider().frame(height: 32)

            Button(action: onDismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("키보드 내리기")
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func formatButton(_ image: String, title: String, command: StudyInlineCommand) -> some View {
        let isActive = activeCommands.contains(command)
        return Button { onCommand(command) } label: {
            formatLabel(image, title: title, isActive: isActive)
        }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isActive ? "켬" : "끔")
    }

    private func blockFormatButton(
        _ image: String,
        title: String,
        kind: StudyPageBlockKind
    ) -> some View {
        let isActive = activeBlockKind == kind
        return Button { onToggleBlockKind(kind) } label: {
            formatLabel(image, title: title, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "켬" : "끔")
    }

    private func formatLabel(_ image: String, title: String, isActive: Bool = false) -> some View {
        VStack(spacing: 2) {
            Image(systemName: image).font(.body)
            Text(title).font(.system(size: 9))
        }
        .frame(width: 43, height: 40)
        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        .background(
            isActive ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
}

private struct StudyHighlightPalette: View {
    let onSelect: (Color?) -> Void
    let onCustom: () -> Void

    private let colors: [(String, Color)] = [
        ("노랑", .yellow.opacity(0.76)),
        ("초록", .green.opacity(0.68)),
        ("파랑", .blue.opacity(0.66)),
        ("분홍", .pink.opacity(0.70)),
        ("보라", .purple.opacity(0.68))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            paletteButton("색 지우기", color: nil)
            Divider().padding(.vertical, 5)
            ForEach(Array(colors.enumerated()), id: \.offset) { _, item in
                paletteButton(item.0, color: item.1)
            }
            Divider().padding(.vertical, 5)
            Button(action: onCustom) {
                Label("사용자 지정…", systemImage: "paintpalette")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 220)
    }

    private func paletteButton(_ title: String, color: Color?) -> some View {
        Button { onSelect(color) } label: {
            HStack(spacing: 12) {
                if let color {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(color)
                        .overlay { RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.35)) }
                        .frame(width: 28, height: 22)
                } else {
                    Image(systemName: "eraser")
                        .frame(width: 28, height: 22)
                }
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}

private enum StudySlashCommand: String, CaseIterable, Identifiable {
    case text, heading1, heading2, heading3, bulletedList, numberedList, toDo, quote, callout, code, divider
    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "본문"
        case .heading1: "제목 1"
        case .heading2: "제목 2"
        case .heading3: "제목 3"
        case .bulletedList: "글머리 목록"
        case .numberedList: "번호 목록"
        case .toDo: "할 일"
        case .quote: "인용"
        case .callout: "메모 상자"
        case .code: "코드 블록"
        case .divider: "구분선"
        }
    }

    var subtitle: String {
        switch self {
        case .text: "일반 문장을 작성합니다."
        case .heading1, .heading2, .heading3: "내용을 구분하는 제목입니다."
        case .bulletedList: "순서 없는 항목을 이어서 작성합니다."
        case .numberedList: "번호가 자동으로 이어집니다."
        case .toDo: "직접 체크할 수 있는 항목입니다."
        case .quote: "인용문이나 예문을 강조합니다."
        case .callout: "기억할 내용을 눈에 띄게 표시합니다."
        case .code: "여러 줄을 고정폭 글꼴로 작성합니다."
        case .divider: "내용 사이를 선으로 구분합니다."
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat"
        case .bulletedList: "list.bullet"
        case .numberedList: "list.number"
        case .toDo: "checkmark.square"
        case .quote: "quote.opening"
        case .callout: "lightbulb"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        }
    }

    var kind: StudyPageBlockKind { StudyPageBlockKind(rawValue: rawValue) ?? .text }

    func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        let aliases: String
        switch self {
        case .toDo: aliases = "todo 체크 할일"
        case .code: aliases = "code 코드"
        case .quote: aliases = "quote 인용 예문"
        case .callout: aliases = "callout 메모 강조"
        default: aliases = title.lowercased()
        }
        return title.lowercased().contains(normalized) || aliases.contains(normalized)
    }
}

private struct StudySlashCommandMenu: View {
    let query: String
    let onSelect: (StudySlashCommand) -> Void

    private var commands: [StudySlashCommand] {
        StudySlashCommand.allCases.filter { $0.matches(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                Text("기본 블록")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                ForEach(commands) { command in
                    Button { onSelect(command) } label: {
                        HStack(spacing: 11) {
                            Image(systemName: command.systemImage)
                                .frame(width: 28, height: 28)
                                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(command.title).font(.subheadline.weight(.medium))
                                Text(command.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }

                if commands.isEmpty {
                    ContentUnavailableView("일치하는 블록이 없습니다", systemImage: "magnifyingglass")
                        .frame(height: 120)
                }
            }
        }
        .frame(width: 330, height: min(CGFloat(max(commands.count, 2)) * 58 + 45, 430))
    }
}

private struct StudyBlockPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (StudySlashCommand) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("기본 블록") {
                    ForEach(StudySlashCommand.allCases) { command in
                        Button {
                            dismiss()
                            onSelect(command)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: command.systemImage)
                                    .frame(width: 32, height: 32)
                                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(command.title)
                                        .foregroundStyle(.primary)
                                    Text(command.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("블록 추가")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 620)
        #endif
    }
}

private struct StudyCategoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyPageCategory.createdAt) private var categories: [StudyPageCategory]
    @Query private var memos: [StudyMemo]
    @Bindable var memo: StudyMemo

    @StateObject private var viewModel = StudyCategoryPickerViewModel()
    @State private var newName = ""
    @State private var selectedColor = StudyCategoryColor.gray
    @State private var isCreatingCategory = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if isCreatingCategory {
                    Section("분류 이름") {
                        TextField("예: 받아쓰기", text: $newName)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit(createAndAssign)
                    }

                    Section("색상") {
                        HStack(spacing: 12) {
                            ForEach(StudyCategoryColor.allCases) { color in
                                Button {
                                    selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 30, height: 30)
                                        .overlay {
                                            if selectedColor == color {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(color.title) 분류 색상")
                                .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                            }
                        }
                    }

                    Section {
                        Button("추가하고 지정", action: createAndAssign)
                            .frame(maxWidth: .infinity)
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Section("분류 선택") {
                        Button {
                            if viewModel.assign(nil, to: memo, in: modelContext) {
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Label("분류 없음", systemImage: "tag.slash")
                                Spacer()
                                if memo.categoryID.isEmpty { Image(systemName: "checkmark") }
                            }
                        }

                        ForEach(categories) { category in
                            Button {
                                if viewModel.assign(category, to: memo, in: modelContext) {
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    StudyCategoryBadge(name: category.name, colorRawValue: category.colorRawValue)
                                    Spacer()
                                    if memo.categoryID == category.id.uuidString { Image(systemName: "checkmark") }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteCategories)
                    }

                    Section {
                        Button {
                            showCategoryCreation()
                        } label: {
                            Label("분류 추가하기", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isCreatingCategory ? "새 분류" : "분류 선택")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isCreatingCategory && !categories.isEmpty {
                        Button {
                            isCreatingCategory = false
                            isNameFocused = false
                        } label: {
                            Label("분류 선택", systemImage: "chevron.left")
                        }
                    } else {
                        Button("닫기") { dismiss() }
                    }
                }
                if isCreatingCategory && !categories.isEmpty {
                    ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { if categories.isEmpty { showCategoryCreation() } }
        .alert(item: $viewModel.errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private func showCategoryCreation() {
        isCreatingCategory = true
        Task { @MainActor in
            await Task.yield()
            isNameFocused = true
        }
    }

    private func createAndAssign() {
        let didAssign = viewModel.createAndAssign(
            name: newName,
            color: selectedColor,
            existingCategories: categories,
            to: memo,
            in: modelContext
        )
        if didAssign {
            dismiss()
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        let categoriesToDelete = offsets.map { categories[$0] }
        viewModel.deleteCategories(categoriesToDelete, affecting: memos, in: modelContext)
        if categories.count <= offsets.count { showCategoryCreation() }
    }
}

struct StudyCategoryBadge: View {
    let name: String
    let colorRawValue: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.medium))
            .foregroundStyle(color.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.color.opacity(0.13), in: Capsule())
    }

    private var color: StudyCategoryColor {
        StudyCategoryColor(rawValue: colorRawValue) ?? .gray
    }
}

enum StudyCategoryColor: String, CaseIterable, Identifiable {
    case gray, red, orange, yellow, green, blue, purple, pink
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gray: "회색"
        case .red: "빨강"
        case .orange: "주황"
        case .yellow: "노랑"
        case .green: "초록"
        case .blue: "파랑"
        case .purple: "보라"
        case .pink: "분홍"
        }
    }

    var color: Color {
        switch self {
        case .gray: .gray
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

struct ImportedMarkdownPage {
    var title: String
    var categoryName: String
    var body: String
}

private enum StudyMarkdownError: LocalizedError {
    case invalidFile
    var errorDescription: String? { "UTF-8 형식의 올바른 Markdown 파일이 아닙니다." }
}

private extension UTType {
    static let markdownDocument = UTType("net.daringfireball.markdown") ?? .plainText
}

private struct StudyMarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownDocument, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDocument] }
    var markdown = ""

    init(markdown: String = "") { self.markdown = markdown }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let markdown = String(data: data, encoding: .utf8) else {
            throw StudyMarkdownError.invalidFile
        }
        self.markdown = markdown
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(markdown.utf8))
    }
}

enum StudyMarkdownCodec {
    static func importPage(_ markdown: String) -> ImportedMarkdownPage {
        var lines = markdown.components(separatedBy: .newlines)
        var title = ""
        var categoryName = ""

        if let firstContent = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[firstContent].hasPrefix("# ") {
            title = String(lines[firstContent].dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.remove(at: firstContent)
        }

        if let categoryIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("<!-- vocaday-category:")
        }) {
            categoryName = lines[categoryIndex]
                .replacingOccurrences(of: "<!-- vocaday-category:", with: "")
                .replacingOccurrences(of: "-->", with: "")
                .trimmingCharacters(in: .whitespaces)
            lines.remove(at: categoryIndex)
        }

        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { lines.removeFirst() }
        return ImportedMarkdownPage(title: title, categoryName: categoryName, body: lines.joined(separator: "\n"))
    }

    static func exportPage(title: String, categoryName: String, body: String) -> String {
        var sections: [String] = []
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "제목 없음" : title
        sections.append("# \(safeTitle)")
        if !categoryName.isEmpty { sections.append("<!-- vocaday-category: \(categoryName) -->") }
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sections.append(body) }
        return sections.joined(separator: "\n\n") + "\n"
    }
}

enum StudyNotionCodec {
    static func blocks(for memo: StudyMemo) -> [StudyPageBlock] {
        let stored = memo.blocks
        if stored.contains(where: { !$0.richTextData.isEmpty }) {
            return stored.map { block in
                guard block.kind == .text,
                      let conversion = StudyMarkdownBlockShortcut.conversion(for: attributedText(for: block)) else {
                    return block
                }
                var converted = block
                converted.kind = conversion.kind
                converted.text = String(conversion.remainder.characters)
                converted.richTextData = encode(conversion.remainder)
                return converted
            }
        }
        return blocks(from: StudyMarkdownMigration.markdown(for: memo))
    }

    static func blocks(from markdown: String) -> [StudyPageBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "☐ ", with: "- [ ] ")
            .replacingOccurrences(of: "☑ ", with: "- [x] ")
            .replacingOccurrences(of: "❝ ", with: "> ")
        let lines = normalized.components(separatedBy: .newlines)
        var result: [StudyPageBlock] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        func append(_ kind: StudyPageBlockKind, _ source: String, checked: Bool = false) {
            let attributed = kind == .code ? AttributedString(source) : parseInline(source)
            var block = StudyPageBlock(kind: kind, text: String(attributed.characters), isChecked: checked)
            block.richTextData = encode(attributed)
            result.append(block)
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    append(.code, codeLines.joined(separator: "\n"))
                    codeLines.removeAll()
                }
                isInCodeBlock.toggle()
                continue
            }
            if isInCodeBlock {
                codeLines.append(rawLine)
                continue
            }
            guard !trimmed.isEmpty else { continue }

            if trimmed == "---" || trimmed == "***" {
                result.append(StudyPageBlock(kind: .divider))
            } else if trimmed.hasPrefix("### ") {
                append(.heading3, String(trimmed.dropFirst(4)))
            } else if trimmed.hasPrefix("## ") {
                append(.heading2, String(trimmed.dropFirst(3)))
            } else if trimmed.hasPrefix("# ") {
                append(.heading1, String(trimmed.dropFirst(2)))
            } else if trimmed.lowercased().hasPrefix("- [x] ") {
                append(.toDo, String(trimmed.dropFirst(6)), checked: true)
            } else if trimmed.hasPrefix("- [ ] ") {
                append(.toDo, String(trimmed.dropFirst(6)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                append(.bulletedList, String(trimmed.dropFirst(2)))
            } else if let range = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                append(.numberedList, String(trimmed[range.upperBound...]))
            } else if trimmed.hasPrefix("> **메모**") {
                continue
            } else if trimmed.hasPrefix("> ") {
                append(.quote, String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("|") {
                append(.table, trimmed)
            } else {
                append(.text, rawLine)
            }
        }

        if isInCodeBlock || !codeLines.isEmpty {
            append(.code, codeLines.joined(separator: "\n"))
        }
        return result.isEmpty ? [StudyPageBlock()] : result
    }

    static func attributedText(for block: StudyPageBlock) -> AttributedString {
        if let data = Data(base64Encoded: block.richTextData),
           let decoded = try? JSONDecoder().decode(AttributedString.self, from: data) {
            return decoded
        }
        return parseInline(block.text)
    }

    static func encode(_ text: AttributedString) -> String {
        guard let data = try? JSONEncoder().encode(text) else { return "" }
        return data.base64EncodedString()
    }

    static func markdown(from blocks: [StudyPageBlock], texts: [UUID: AttributedString]) -> String {
        blocks.compactMap { block -> String? in
            let text = texts[block.id] ?? attributedText(for: block)
            let inline = inlineMarkdown(from: text)
            let plain = String(text.characters)
            switch block.kind {
            case .text: return inline
            case .heading1: return inline.isEmpty ? nil : "# \(inline)"
            case .heading2: return inline.isEmpty ? nil : "## \(inline)"
            case .heading3: return inline.isEmpty ? nil : "### \(inline)"
            case .bulletedList: return inline.isEmpty ? nil : "- \(inline)"
            case .numberedList: return inline.isEmpty ? nil : "1. \(inline)"
            case .toDo: return inline.isEmpty ? nil : "- [\(block.isChecked ? "x" : " ")] \(inline)"
            case .quote: return inline.isEmpty ? nil : "> \(inline)"
            case .callout: return inline.isEmpty ? nil : "> **메모**  \n> \(inline)"
            case .code: return plain.isEmpty ? nil : "```\n\(plain)\n```"
            case .divider: return "---"
            case .toggle: return inline
            case .table:
                if !block.tableColumns.isEmpty {
                    return markdownTable(columns: block.tableColumns, rows: block.tableRows)
                }
                return plain
            }
        }.joined(separator: "\n\n")
    }

    private static func parseInline(_ source: String) -> AttributedString {
        var output = AttributedString()
        var cursor = source.startIndex

        while let opening = source[cursor...].range(of: "<mark>") {
            output.append(parseInlineFragment(String(source[cursor..<opening.lowerBound])))
            let contentStart = opening.upperBound
            guard let closing = source[contentStart...].range(of: "</mark>") else {
                output.append(parseInlineFragment(String(source[opening.lowerBound...])))
                return output
            }

            var highlighted = parseInlineFragment(String(source[contentStart..<closing.lowerBound]))
            highlighted.backgroundColor = Color.yellow.opacity(0.76)
            output.append(highlighted)
            cursor = closing.upperBound
        }

        output.append(parseInlineFragment(String(source[cursor...])))
        return output
    }

    private static func parseInlineFragment(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    private static func inlineMarkdown(from text: AttributedString) -> String {
        var output = ""
        for run in text.runs {
            var value = String(text[run.range].characters)
            let intent = run.inlinePresentationIntent
            if intent?.contains(.code) == true {
                value = "`\(value.replacingOccurrences(of: "`", with: "\\`"))`"
            } else {
                if intent?.contains(.stronglyEmphasized) == true { value = "**\(value)**" }
                if intent?.contains(.emphasized) == true { value = "*\(value)*" }
                if run.underlineStyle != nil { value = "<u>\(value)</u>" }
                if run.strikethroughStyle != nil { value = "~~\(value)~~" }
                if run.backgroundColor != nil { value = "<mark>\(value)</mark>" }
            }
            if let link = run.link { value = "[\(value)](\(link.absoluteString))" }
            output += value
        }
        return output
    }

    private static func markdownTable(columns: [String], rows: [[String]]) -> String {
        let header = "| " + columns.joined(separator: " | ") + " |"
        let divider = "| " + columns.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.map { row in
            let cells = columns.indices.map { index in index < row.count ? row[index] : "" }
            return "| " + cells.joined(separator: " | ") + " |"
        }
        return ([header, divider] + body).joined(separator: "\n")
    }
}

enum StudyMarkdownMigration {
    static func markdown(for memo: StudyMemo) -> String {
        if !memo.richTextData.isEmpty,
           let data = Data(base64Encoded: memo.richTextData),
           let attributed = try? JSONDecoder().decode(AttributedString.self, from: data) {
            return markdown(from: attributed)
        }
        if !memo.plainTextContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizeLegacyGlyphs(in: memo.plainTextContent)
        }
        return markdown(from: memo.blocks)
    }

    static func markdown(from blocks: [StudyPageBlock]) -> String {
        blocks.compactMap { block -> String? in
            switch block.kind {
            case .text: block.text
            case .heading1: block.text.isEmpty ? nil : "# \(block.text)"
            case .heading2: block.text.isEmpty ? nil : "## \(block.text)"
            case .heading3: block.text.isEmpty ? nil : "### \(block.text)"
            case .bulletedList: block.text.isEmpty ? nil : "- \(block.text)"
            case .numberedList: block.text.isEmpty ? nil : "1. \(block.text)"
            case .toDo: block.text.isEmpty ? nil : "- [\(block.isChecked ? "x" : " ")] \(block.text)"
            case .toggle: [block.text, block.detail].filter { !$0.isEmpty }.joined(separator: "\n")
            case .quote: block.text.isEmpty ? nil : "> \(block.text)"
            case .callout: block.text.isEmpty ? nil : "> **메모**  \n> \(block.text)"
            case .code: block.text.isEmpty ? nil : "```\n\(block.text)\n```"
            case .divider: "---"
            case .table: markdownTable(columns: block.tableColumns, rows: block.tableRows)
            }
        }.joined(separator: "\n\n")
    }

    static func preview(from markdown: String) -> String {
        let text = normalizeLegacyGlyphs(in: markdown)
            .replacingOccurrences(of: #"<!--.*?-->"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]*\)"#, with: "이미지", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"^(#{1,6}\s+|>\s+|-\s\[[ xX]\]\s+|-\s+|\d+\.\s+)"#, with: "", options: [.regularExpression, .anchored])
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "내용을 입력해 보세요."
    }

    private static func markdown(from attributed: AttributedString) -> String {
        var lines: [String] = []
        var lineStart = attributed.startIndex
        while lineStart < attributed.endIndex {
            let newline = attributed.characters[lineStart...].firstIndex(of: "\n")
            let lineEnd = newline ?? attributed.endIndex
            lines.append(markdownLine(from: attributed[lineStart..<lineEnd]))
            guard let newline else { break }
            lineStart = attributed.characters.index(after: newline)
        }
        return normalizeLegacyGlyphs(in: lines.joined(separator: "\n"))
    }

    private static func markdownLine(from line: AttributedSubstring) -> String {
        let plain = String(line.characters)
        if plain.allSatisfy({ $0 == "─" }) && !plain.isEmpty { return "---" }
        var rendered = ""
        for run in line.runs {
            var value = String(line[run.range].characters)
            let intent = run.inlinePresentationIntent
            if intent?.contains(.code) == true {
                value = "`\(value)`"
            } else {
                if intent?.contains(.stronglyEmphasized) == true { value = "**\(value)**" }
                if intent?.contains(.emphasized) == true { value = "*\(value)*" }
                if run.strikethroughStyle != nil { value = "~~\(value)~~" }
            }
            if let link = run.link { value = "[\(value)](\(link.absoluteString))" }
            rendered += value
        }
        if let presentation = line.runs.first?.presentationIntent {
            for component in presentation.components.reversed() {
                if case .header(let level) = component.kind {
                    return String(repeating: "#", count: max(1, min(level, 6))) + " " + rendered
                }
            }
        }
        return rendered
    }

    private static func normalizeLegacyGlyphs(in text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            if line.hasPrefix("☐ ") { return "- [ ] " + line.dropFirst(2) }
            if line.hasPrefix("☑ ") { return "- [x] " + line.dropFirst(2) }
            if line.hasPrefix("❝ ") { return "> " + line.dropFirst(2) }
            if line.hasPrefix("• ") { return "- " + line.dropFirst(2) }
            if line.allSatisfy({ $0 == "─" }) && !line.isEmpty { return "---" }
            return line
        }.joined(separator: "\n")
    }

    private static func markdownTable(columns: [String], rows: [[String]]) -> String? {
        guard !columns.isEmpty else { return nil }
        let header = "| " + columns.joined(separator: " | ") + " |"
        let divider = "| " + columns.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.map { row in
            let cells = columns.indices.map { index in index < row.count ? row[index] : "" }
            return "| " + cells.joined(separator: " | ") + " |"
        }
        return ([header, divider] + body).joined(separator: "\n")
    }
}

enum StudyPageStyle {
    static var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    static var hover: Color { Color.secondary.opacity(0.09) }
}

#Preview {
    NavigationStack { StudyMemosView() }
        .modelContainer(for: [StudyMemo.self, StudyPageCategory.self], inMemory: true)
}
