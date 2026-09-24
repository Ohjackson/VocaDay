import SwiftUI

struct WordDataTable: View {
    let title: String
    let words: [VocaWord]
    var hideKoreanMeaning = false
    var allowsSelection = false
    var showsTitle = true
    var showsWordDetails = false
    var emptyTitle: String = "이 데이에 저장된 단어가 없습니다."
    var isEditingRows = false
    var revealsHiddenKoreanWhilePressing = false
    var onEnglishTap: (VocaWord) -> Void = { _ in }
    var onEnglishLongPress: ((VocaWord) -> Void)?
    var onEditWord: (VocaWord) -> Void = { _ in }
    var onDeleteWord: (VocaWord) -> Void = { _ in }
    @Binding var selectedWordIDs: Set<UUID>
    @GestureState private var pressedKoreanWordID: UUID?
    @State private var lingeringKoreanWordID: UUID?
    @State private var lingeringRevealToken = UUID()
    @State private var expandedWordID: UUID?
    @State private var usesRowSpecificDetails = false
    @State private var measuredContainerWidth: CGFloat = 0

    private static let twoColumnMinWidth: CGFloat = 900

    var body: some View {
        Group {
            #if os(iOS)
            mobileWordList
            #else
            fullWidthTable
            #endif
        }
            .onChange(of: pressedKoreanWordID) { previousWordID, currentWordID in
                handleKoreanMeaningPressChange(
                    previousWordID: previousWordID,
                    currentWordID: currentWordID
                )
            }
            .onChange(of: showsWordDetails) { _, _ in
                usesRowSpecificDetails = false
                expandedWordID = nil
            }
            .onChange(of: words.map(\.id)) { _, currentWordIDs in
                guard let expandedWordID, !currentWordIDs.contains(expandedWordID) else { return }
                self.expandedWordID = nil
            }
    }

    #if os(iOS)
    private var mobileWordList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text("\(words.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if words.isEmpty {
                EmptyStateView(title: emptyTitle, systemImage: "text.page")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                        mobileWordCard(index: index, word: word)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func mobileWordCard(index: Int, word: VocaWord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    toggleDetails(for: word)
                } label: {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(word.english) 세부 정보")
                .accessibilityHint("두 번 탭하여 예문과 메모를 열거나 닫습니다.")

                mobileEnglishButton(for: word)

                if isEditingRows {
                    Button {
                        onEditWord(word)
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(word.english) 편집")

                    Button(role: .destructive) {
                        onDeleteWord(word)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(word.english) 삭제")
                }
            }

            mobileKoreanMeaning(for: word)

            if word.wrongCount > 0 {
                Label("다시 학습 \(word.wrongCount)회", systemImage: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isShowingDetails(for: word) {
                Divider()
                mobileDetailLine(label: "영어 예문", value: word.exampleEn)
                mobileDetailLine(label: "예문 번역", value: word.exampleKo)
                mobileDetailLine(label: "메모", value: word.note)
                mobileDetailLine(label: "태그", value: word.toeicTag)
            }
        }
        .padding(14)
        .background(rowBackground(isHeader: false, isSelected: selectedWordIDs.contains(word.id)))
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    selectedWordIDs.contains(word.id) ? Color.accentColor.opacity(0.7) : AppTheme.softStroke,
                    lineWidth: selectedWordIDs.contains(word.id) ? 2 : 1
                )
        }
        .animation(.easeInOut(duration: 0.16), value: selectedWordIDs.contains(word.id))
        .animation(.easeInOut(duration: 0.18), value: expandedWordID)
    }

    @ViewBuilder
    private func mobileEnglishButton(for word: VocaWord) -> some View {
        let button = Button {
            if allowsSelection {
                toggleSelection(of: word)
            } else {
                onEnglishTap(word)
            }
        } label: {
            HStack(spacing: 8) {
                Text(word.english)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if allowsSelection, selectedWordIDs.contains(word.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if let onEnglishLongPress {
            button.simultaneousGesture(
                LongPressGesture(minimumDuration: 1)
                    .onEnded { didPress in
                        guard didPress else { return }
                        onEnglishLongPress(word)
                    }
            )
        } else {
            button
        }
    }

    @ViewBuilder
    private func mobileKoreanMeaning(for word: VocaWord) -> some View {
        let meaning = Text(koreanMeaningText(for: word))
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 9))

        if hideKoreanMeaning, revealsHiddenKoreanWhilePressing {
            meaning.simultaneousGesture(koreanPressGesture(for: word))
        } else {
            meaning
        }
    }

    private func mobileDetailLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(display(value))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif

    private var fullWidthTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitle {
                HStack {
                    Text(title)
                        .font(.headline)

                    Spacer()

                    Text("\(words.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if words.isEmpty {
                EmptyStateView(
                    title: emptyTitle,
                    systemImage: "text.page"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else if measuredContainerWidth > 0 {
                if isTwoColumnLayout {
                    twoColumnTable
                } else {
                    singleColumnTable
                }
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.cardBackground)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredContainerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        measuredContainerWidth = newValue
                    }
            }
        )
    }

    private var isTwoColumnLayout: Bool {
        measuredContainerWidth >= Self.twoColumnMinWidth
    }

    private var singleColumnTable: some View {
        let availableWidth = max(measuredContainerWidth - (isEditingRows ? rowActionWidth : 0), 1)
        let widths = columnWidths(totalWidth: availableWidth)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if isEditingRows {
                    Color.clear
                        .frame(width: rowActionWidth)
                }

                proportionalRow(
                    values: ["#", "영단어", "한국어 뜻"],
                    widths: widths,
                    isHeader: true
                )
            }

            Divider()

            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                wordRow(index: index, word: word, widths: widths)
                Divider()
            }
        }
    }

    private var indexedWords: [(index: Int, word: VocaWord)] {
        Array(words.enumerated()).map { (index: $0.offset, word: $0.element) }
    }

    private var leftColumnIndexedWords: [(index: Int, word: VocaWord)] {
        indexedWords.filter { $0.index.isMultiple(of: 2) }
    }

    private var rightColumnIndexedWords: [(index: Int, word: VocaWord)] {
        indexedWords.filter { !$0.index.isMultiple(of: 2) }
    }

    private var twoColumnTable: some View {
        let columnSpacing: CGFloat = 24
        let columnWidth = max((measuredContainerWidth - columnSpacing) / 2, 1)

        return HStack(alignment: .top, spacing: columnSpacing) {
            tableColumn(indexedWords: leftColumnIndexedWords, containerWidth: columnWidth)
            tableColumn(indexedWords: rightColumnIndexedWords, containerWidth: columnWidth)
        }
    }

    private func tableColumn(indexedWords: [(index: Int, word: VocaWord)], containerWidth: CGFloat) -> some View {
        let availableWidth = max(containerWidth - (isEditingRows ? rowActionWidth : 0), 1)
        let widths = columnWidths(totalWidth: availableWidth)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if isEditingRows {
                    Color.clear
                        .frame(width: rowActionWidth)
                }

                proportionalRow(
                    values: ["#", "영단어", "한국어 뜻"],
                    widths: widths,
                    isHeader: true
                )
            }

            Divider()

            ForEach(indexedWords, id: \.word.id) { entry in
                wordRow(index: entry.index, word: entry.word, widths: widths)
                Divider()
            }
        }
        .frame(width: containerWidth, alignment: .topLeading)
    }

    private func columnWidths(totalWidth: CGFloat) -> [CGFloat] {
        [
            totalWidth * 0.10,
            totalWidth * 0.45,
            totalWidth * 0.45
        ]
    }

    private var rowActionWidth: CGFloat {
        98
    }

    private func wordRow(index: Int, word: VocaWord, widths: [CGFloat]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if isEditingRows {
                rowActions(for: word)
                    .frame(width: rowActionWidth, alignment: .top)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                wordMainRow(index: index, word: word, widths: widths)

                if isShowingDetails(for: word) {
                    wordDetailLines(for: word)
                }
            }
            .background(rowBackground(isHeader: false, isSelected: selectedWordIDs.contains(word.id)))
        }
        .animation(.easeInOut(duration: 0.2), value: isEditingRows)
        .animation(.easeInOut(duration: 0.15), value: selectedWordIDs.contains(word.id))
        .animation(.easeInOut(duration: 0.18), value: expandedWordID)
    }

    private func wordMainRow(index: Int, word: VocaWord, widths: [CGFloat]) -> some View {
        let values = [
            "\(index + 1)",
            word.english,
            koreanMeaningText(for: word)
        ]

        return HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { columnIndex, value in
                interactiveCell(
                    value: value,
                    word: word,
                    columnIndex: columnIndex,
                    width: widths[columnIndex]
                )
                    .overlay(alignment: .trailing) {
                        if columnIndex == 1, allowsSelection, selectedWordIDs.contains(word.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.trailing, 10)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if columnIndex < values.count - 1 {
                            Rectangle()
                                .fill(AppTheme.softStroke)
                                .frame(width: 0.5)
                        }
                    }
            }
        }
        .background(rowBackground(isHeader: false, isSelected: selectedWordIDs.contains(word.id)))
    }

    @ViewBuilder
    private func interactiveCell(
        value: String,
        word: VocaWord,
        columnIndex: Int,
        width: CGFloat
    ) -> some View {
        let baseCell = cell(
            value: value,
            count: columnIndex == 0 ? word.wrongCount : nil,
            index: columnIndex,
            isHeader: false
        )
        .frame(width: width, height: 44, alignment: columnIndex == 0 ? .center : .leading)
        .padding(.horizontal, columnIndex == 0 ? 2 : 6)
        .background(
            columnIndex == 0 && isShowingDetails(for: word)
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            switch columnIndex {
            case 0:
                toggleDetails(for: word)
            case 1:
                if allowsSelection {
                    toggleSelection(of: word)
                } else {
                    onEnglishTap(word)
                }
            default:
                break
            }
        }
        .accessibilityHint(columnIndex == 0 ? "이 단어의 상세 정보를 열거나 닫습니다." : "")

        if columnIndex == 1, let onEnglishLongPress {
            baseCell.simultaneousGesture(
                LongPressGesture(minimumDuration: 1)
                    .onEnded { didPress in
                        guard didPress else { return }
                        onEnglishLongPress(word)
                    }
            )
        } else if columnIndex == 2, hideKoreanMeaning, revealsHiddenKoreanWhilePressing {
            baseCell.simultaneousGesture(koreanPressGesture(for: word))
        } else {
            baseCell
        }
    }

    private func toggleSelection(of word: VocaWord) {
        if selectedWordIDs.contains(word.id) {
            selectedWordIDs.remove(word.id)
        } else {
            selectedWordIDs.insert(word.id)
        }
    }

    private func toggleDetails(for word: VocaWord) {
        usesRowSpecificDetails = true
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedWordID = expandedWordID == word.id ? nil : word.id
        }
    }

    private func isShowingDetails(for word: VocaWord) -> Bool {
        if usesRowSpecificDetails {
            return expandedWordID == word.id
        }
        return showsWordDetails
    }

    private func rowActions(for word: VocaWord) -> some View {
        HStack(spacing: 6) {
            Button {
                onEditWord(word)
            } label: {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(word.english) 편집")

            Button(role: .destructive) {
                onDeleteWord(word)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(word.english) 삭제")
        }
        .padding(.top, 3)
        .background(rowBackground(isHeader: false, isSelected: selectedWordIDs.contains(word.id)))
    }

    private func proportionalRow(values: [String], count: Int? = nil, widths: [CGFloat], isHeader: Bool, isSelected: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                cell(value: value, count: index == 0 ? count : nil, index: index, isHeader: isHeader)
                    .frame(width: widths[index], height: 44, alignment: index == 0 ? .center : .leading)
                    .padding(.horizontal, index == 0 ? 2 : 6)
                    .overlay(alignment: .trailing) {
                        if index < values.count - 1 {
                            Rectangle()
                                .fill(AppTheme.softStroke)
                                .frame(width: 0.5)
                        }
                    }
            }
        }
        .background(rowBackground(isHeader: isHeader, isSelected: isSelected))
    }

    private func wordDetailLines(for word: VocaWord) -> some View {
        let hasExample = !isBlank(word.exampleEn) || !isBlank(word.exampleKo)
        let hasNote = !isBlank(word.note)
        let hasTag = !isBlank(word.toeicTag)

        return VStack(alignment: .leading, spacing: 8) {
            if hasExample {
                VStack(alignment: .leading, spacing: 3) {
                    if !isBlank(word.exampleEn) {
                        Text(word.exampleEn)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !isBlank(word.exampleKo) {
                        Text(word.exampleKo)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if hasNote {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(word.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if hasTag {
                detailTagBadge(word.toeicTag)
            }

            if !hasExample && !hasNote && !hasTag {
                Text("등록된 예문/메모가 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.raisedBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.softStroke)
                .frame(height: 1)
        }
    }

    private func detailTagBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.08), in: Capsule())
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func cell(value: String, count: Int?, index: Int, isHeader: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                Text(value)
            }
            .font(isHeader ? .caption.weight(.semibold) : compactFont(for: index, value: value))
            .minimumScaleFactor(0.45)
            .foregroundStyle(isHeader ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.trailing, !isHeader && index == 1 && allowsSelection ? 28 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: index == 0 ? .center : .leading)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                    .padding(.bottom, 4)
            }
        }
    }

    private func compactFont(for index: Int, value: String) -> Font {
        if value.count > 18 {
            return .caption
        }

        return .subheadline
    }

    private func rowBackground(isHeader: Bool, isSelected: Bool) -> Color {
        if isHeader {
            return Color.secondary.opacity(0.06)
        }

        return isSelected ? Color.accentColor.opacity(0.12) : Color.clear
    }

    private func display(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value
    }

    private func koreanMeaningText(for word: VocaWord) -> String {
        guard hideKoreanMeaning else {
            return display(word.meaningKo)
        }

        if let pressedKoreanWordID {
            return pressedKoreanWordID == word.id ? display(word.meaningKo) : "••••"
        }

        return lingeringKoreanWordID == word.id ? display(word.meaningKo) : "••••"
    }

    private func handleKoreanMeaningPressChange(
        previousWordID: UUID?,
        currentWordID: UUID?
    ) {
        if currentWordID != nil {
            lingeringRevealToken = UUID()
            lingeringKoreanWordID = nil
            return
        }

        guard let previousWordID else { return }
        keepKoreanMeaningVisibleAfterRelease(wordID: previousWordID)
    }

    private func keepKoreanMeaningVisibleAfterRelease(wordID: UUID) {
        let revealToken = UUID()
        lingeringRevealToken = revealToken
        lingeringKoreanWordID = wordID

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard lingeringRevealToken == revealToken else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                lingeringKoreanWordID = nil
            }
        }
    }

    private func koreanPressGesture(for word: VocaWord) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2, maximumDistance: 8)
            .updating($pressedKoreanWordID) { _, state, _ in
                state = word.id
            }
    }
}
