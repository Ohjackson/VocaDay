import SwiftData
import SwiftUI

struct CreateStudyPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var kind: StudyPageKind = .markdown
    @State private var iconName = "doc.richtext"

    private let icons = [
        "doc.richtext", "tablecells", "book.closed", "pencil.and.list.clipboard",
        "checklist", "text.quote", "lightbulb", "graduationcap"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("페이지 이름") {
                    TextField("예: 토익 오답 노트", text: $title)
                        .onSubmit(create)
                }

                Section {
                    ForEach(StudyPageKind.allCases) { item in
                        Button {
                            kind = item
                            iconName = item.systemImage
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.systemImage)
                                    .font(.title3)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if kind == item {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("페이지 형식")
                } footer: {
                    Text("페이지 형식은 만든 뒤 바꿀 수 없습니다. 내용과 표 구성은 언제든 수정할 수 있어요.")
                }

                Section("아이콘") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46))], spacing: 10) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(iconName == icon ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(iconName == icon ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("새 학습 페이지")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("만들기", action: create)
                        .disabled(cleanTitle.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
        #endif
    }

    private var cleanTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        guard !cleanTitle.isEmpty else { return }

        let columns: [StudyTableColumn]
        if kind == .table {
            columns = [
                StudyTableColumn(title: "항목", kind: .text),
                StudyTableColumn(title: "내용", kind: .text),
                StudyTableColumn(title: "완료", kind: .checkbox)
            ]
        } else {
            columns = []
        }

        let page = CustomStudyPage(
            title: cleanTitle,
            iconName: iconName,
            kind: kind,
            markdown: kind == .markdown ? "# \(cleanTitle)\n\n여기에 학습 내용을 기록하세요." : "",
            columns: columns
        )
        modelContext.insert(page)
        try? modelContext.save()
        dismiss()
    }
}

struct CustomStudyPageDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var page: CustomStudyPage

    @State private var isRenaming = false
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        Group {
            switch page.kind {
            case .markdown:
                MarkdownStudyPageView(page: page)
            case .table:
                TableStudyPageView(page: page)
            }
        }
        .navigationTitle(page.title)
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Menu {
                    Button {
                        isRenaming = true
                    } label: {
                        Label("이름과 아이콘 변경", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("페이지 삭제", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("페이지 메뉴")
            }
        }
        .sheet(isPresented: $isRenaming) {
            RenameStudyPageView(page: page)
        }
        .confirmationDialog("‘\(page.title)’ 페이지를 삭제할까요?", isPresented: $isShowingDeleteConfirmation) {
            Button("삭제", role: .destructive) {
                modelContext.delete(page)
                try? modelContext.save()
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("페이지 안의 모든 내용도 함께 삭제되며 되돌릴 수 없습니다.")
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

private struct RenameStudyPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var page: CustomStudyPage

    @State private var draftTitle: String
    @State private var draftIcon: String

    private let icons = [
        "doc.richtext", "tablecells", "book.closed", "pencil.and.list.clipboard",
        "checklist", "text.quote", "lightbulb", "graduationcap"
    ]

    init(page: CustomStudyPage) {
        self.page = page
        _draftTitle = State(initialValue: page.title)
        _draftIcon = State(initialValue: page.iconName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("페이지 이름", text: $draftTitle)

                Section("아이콘") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46))], spacing: 10) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                draftIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(draftIcon == icon ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("페이지 정보 편집")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        page.title = cleanTitle
                        page.iconName = draftIcon
                        page.updatedAt = Date()
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(cleanTitle.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }

    private var cleanTitle: String {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MarkdownStudyPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var page: CustomStudyPage

    @State private var draft = ""
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("보기 방식", selection: $isEditing) {
                Text("미리 보기").tag(false)
                Text("편집").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if isEditing {
                VStack(alignment: .leading, spacing: 10) {
                    Text("# 제목, - 목록, **굵게**, | 표 | 형식을 사용할 수 있어요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $draft)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.softStroke)
                        }
                }
                .padding(20)
            } else {
                ScrollView {
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        EmptyStateView(title: "편집을 눌러 학습 내용을 작성하세요.", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        GrammarMarkdownView(markdown: draft)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 900, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(AppTheme.background)
        .onAppear {
            draft = page.markdown
            isEditing = page.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { save() }
        }
        .onDisappear(perform: save)
    }

    private func save() {
        guard page.markdown != draft else { return }
        page.markdown = draft
        page.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct TableStudyPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var page: CustomStudyPage

    @State private var columns: [StudyTableColumn] = []
    @State private var rows: [StudyTableRow] = []
    @State private var isManagingColumns = false

    private var visibleColumns: [StudyTableColumn] {
        columns.filter { !$0.isHidden }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(rows.count)행 · \(columns.count)열")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    isManagingColumns = true
                } label: {
                    Label("열 설정", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)

                Button(action: addRow) {
                    Label("행 추가", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(columns.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if columns.isEmpty {
                EmptyStateView(title: "열 설정에서 첫 번째 열을 만들어 주세요.", systemImage: "tablecells")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleColumns.isEmpty {
                EmptyStateView(title: "모든 열이 숨겨져 있습니다. 열 설정에서 표시할 열을 선택하세요.", systemImage: "eye.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .background(AppTheme.background)
        .onAppear {
            columns = page.columns
            rows = page.rows
        }
        .sheet(isPresented: $isManagingColumns) {
            StudyTableColumnsView(columns: $columns) {
                persist()
            }
        }
    }

    private var table: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    rowNumberCell("#", isHeader: true)
                    ForEach(visibleColumns) { column in
                        Text(column.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: width(for: column), alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                            .background(Color.secondary.opacity(0.08))
                            .overlay(alignment: .trailing) { cellDivider }
                    }
                    Text("")
                        .frame(width: 44)
                }

                ForEach(Array(rows.enumerated()), id: \.element.id) { rowIndex, row in
                    GridRow {
                        rowNumberCell("\(rowIndex + 1)", isHeader: false)

                        ForEach(visibleColumns) { column in
                            tableCell(rowID: row.id, column: column)
                        }

                        Button(role: .destructive) {
                            deleteRow(row.id)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(rowIndex + 1)행 삭제")
                    }
                    Divider()
                }
            }
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.softStroke)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func cell(rowID: UUID, column: StudyTableColumn) -> some View {
        switch column.kind {
        case .text:
            TextField("입력", text: valueBinding(rowID: rowID, columnID: column.id))
                .textFieldStyle(.plain)
        case .number:
            TextField("0", text: valueBinding(rowID: rowID, columnID: column.id))
                .textFieldStyle(.plain)
        case .checkbox:
            Toggle("", isOn: booleanBinding(rowID: rowID, columnID: column.id))
                .labelsHidden()
        case .selection:
            Picker("선택", selection: valueBinding(rowID: rowID, columnID: column.id)) {
                Text("선택 안 함").tag("")
                ForEach(column.options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tableCell(rowID: UUID, column: StudyTableColumn) -> some View {
        cell(rowID: rowID, column: column)
            .frame(width: width(for: column), alignment: .leading)
            .frame(minHeight: 44)
            .padding(.horizontal, 10)
            .overlay(alignment: .trailing) { cellDivider }
    }

    private func rowNumberCell(_ text: String, isHeader: Bool) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .frame(width: 42)
            .frame(minHeight: 44)
            .background(isHeader ? Color.secondary.opacity(0.08) : Color.clear)
            .overlay(alignment: .trailing) { cellDivider }
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(AppTheme.softStroke)
            .frame(width: 0.5)
    }

    private func width(for column: StudyTableColumn) -> CGFloat {
        column.kind == .checkbox ? 86 : 180
    }

    private func valueBinding(rowID: UUID, columnID: UUID) -> Binding<String> {
        Binding {
            rows.first(where: { $0.id == rowID })?.values[columnID.uuidString] ?? ""
        } set: { newValue in
            guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
            rows[index].values[columnID.uuidString] = newValue
            persist()
        }
    }

    private func booleanBinding(rowID: UUID, columnID: UUID) -> Binding<Bool> {
        Binding {
            rows.first(where: { $0.id == rowID })?.values[columnID.uuidString] == "true"
        } set: { newValue in
            guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
            rows[index].values[columnID.uuidString] = newValue ? "true" : "false"
            persist()
        }
    }

    private func addRow() {
        rows.append(StudyTableRow())
        persist()
    }

    private func deleteRow(_ id: UUID) {
        rows.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        page.columns = columns
        page.rows = rows
        try? modelContext.save()
    }
}

private struct StudyTableColumnsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var columns: [StudyTableColumn]
    let onSave: () -> Void

    @State private var isAddingColumn = false

    var body: some View {
        NavigationStack {
            List {
                if columns.isEmpty {
                    ContentUnavailableView("열이 없습니다", systemImage: "rectangle.split.3x1", description: Text("열 추가를 눌러 표의 첫 번째 열을 만드세요."))
                }

                ForEach($columns) { $column in
                    Section {
                        TextField("열 이름", text: $column.title)

                        Picker("입력 형식", selection: $column.kind) {
                            ForEach(StudyTableColumnKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }

                        Toggle("표에 표시", isOn: Binding(
                            get: { !column.isHidden },
                            set: { column.isHidden = !$0 }
                        ))

                        if column.kind == .selection {
                            TextField("선택 항목 (쉼표로 구분)", text: Binding(
                                get: { column.options.joined(separator: ", ") },
                                set: { value in
                                    column.options = value
                                        .components(separatedBy: ",")
                                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                }
                            ))
                        }

                        HStack {
                            Button {
                                move(column.id, offset: -1)
                            } label: {
                                Label("왼쪽", systemImage: "arrow.left")
                            }
                            .disabled(columns.first?.id == column.id)

                            Button {
                                move(column.id, offset: 1)
                            } label: {
                                Label("오른쪽", systemImage: "arrow.right")
                            }
                            .disabled(columns.last?.id == column.id)

                            Spacer()

                            Button("삭제", role: .destructive) {
                                columns.removeAll { $0.id == column.id }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section {
                    Button {
                        columns.append(StudyTableColumn(title: "새 열"))
                    } label: {
                        Label("열 추가", systemImage: "plus")
                    }
                } footer: {
                    Text("열 이름, 입력 형식, 순서와 표시 여부를 자유롭게 바꿀 수 있습니다. 열을 삭제해도 다른 열의 값은 유지됩니다.")
                }
            }
            .navigationTitle("열 설정")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        onSave()
                        dismiss()
                    }
                }
            }
            .onDisappear(perform: onSave)
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 620)
        #endif
    }

    private func move(_ id: UUID, offset: Int) {
        guard let current = columns.firstIndex(where: { $0.id == id }) else { return }
        let destination = current + offset
        guard columns.indices.contains(destination) else { return }
        columns.swapAt(current, destination)
    }
}
