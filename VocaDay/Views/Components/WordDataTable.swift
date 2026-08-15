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
    var onEnglishLongPress: (VocaWord) -> Void = { _ in }
    var onEditWord: (VocaWord) -> Void = { _ in }
    var onDeleteWord: (VocaWord) -> Void = { _ in }
    @Binding var selectedWordIDs: Set<UUID>
    @GestureState private var pressedKoreanWordID: UUID?
    @State private var lingeringKoreanWordID: UUID?
    @State private var lingeringRevealToken = UUID()

    var body: some View {
        fullWidthTable
            .onChange(of: pressedKoreanWordID) { previousWordID, currentWordID in
                handleKoreanMeaningPressChange(
                    previousWordID: previousWordID,
                    currentWordID: currentWordID
                )
            }
    }

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
            } else {
                GeometryReader { proxy in
                    let availableWidth = max(proxy.size.width - (isEditingRows ? rowActionWidth : 0), 1)
                    let widths = columnWidths(totalWidth: availableWidth)

                    VStack(spacing: 0) {
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
                .frame(height: tableHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.cardBackground)
    }

    private func columnWidths(totalWidth: CGFloat) -> [CGFloat] {
        [
            totalWidth * 0.10,
            totalWidth * 0.45,
            totalWidth * 0.45
        ]
    }

    private var tableHeight: CGFloat {
        let headerHeight: CGFloat = 45
        let rowHeight: CGFloat = showsWordDetails ? 134 : 45
        return headerHeight + (CGFloat(words.count) * rowHeight)
    }

    private var rowActionWidth: CGFloat {
        98
    }

    private func wordRow(index: Int, word: VocaWord, widths: [CGFloat]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if isEditingRows {
                rowActions(for: word)
                    .frame(width: rowActionWidth, height: showsWordDetails ? 133 : 44, alignment: .top)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                wordMainRow(index: index, word: word, widths: widths)

                if showsWordDetails {
                    wordDetailLines(for: word)
                }
            }
            .background(rowBackground(isHeader: false, isSelected: selectedWordIDs.contains(word.id)))
        }
        .animation(.easeInOut(duration: 0.2), value: isEditingRows)
        .animation(.easeInOut(duration: 0.15), value: selectedWordIDs.contains(word.id))
    }

    private func wordMainRow(index: Int, word: VocaWord, widths: [CGFloat]) -> some View {
        let values = [
            "\(index + 1)",
            word.english,
            koreanMeaningText(for: word)
        ]

        return HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { columnIndex, value in
                cell(value: value, count: columnIndex == 0 ? word.wrongCount : nil, index: columnIndex, isHeader: false)
                    .frame(width: widths[columnIndex], height: 44, alignment: columnIndex == 0 ? .center : .leading)
                    .padding(.horizontal, columnIndex == 0 ? 2 : 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard columnIndex == 1 else { return }
                        if allowsSelection {
                            toggleSelection(of: word)
                        } else {
                            onEnglishTap(word)
                        }
                    }
                    .simultaneousGesture(englishLongPressGesture(for: word, columnIndex: columnIndex))
                    .simultaneousGesture(koreanPressGesture(for: word, columnIndex: columnIndex))
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

    private func toggleSelection(of word: VocaWord) {
        if selectedWordIDs.contains(word.id) {
            selectedWordIDs.remove(word.id)
        } else {
            selectedWordIDs.insert(word.id)
        }
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
        VStack(alignment: .leading, spacing: 5) {
            detailLine(label: "영어 예문", value: word.exampleEn)
            detailLine(label: "한국어 예문", value: word.exampleKo)
            detailLine(label: "메모", value: word.note)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(Color.secondary.opacity(0.035))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.32))
                .frame(height: 1)
        }
    }

    private func detailLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Text(display(value))
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private func englishLongPressGesture(for word: VocaWord, columnIndex: Int) -> some Gesture {
        LongPressGesture(minimumDuration: columnIndex == 1 ? 1 : .infinity)
            .onEnded { didPress in
                guard didPress, columnIndex == 1 else { return }
                onEnglishLongPress(word)
            }
    }

    private func koreanPressGesture(for word: VocaWord, columnIndex: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2, maximumDistance: 8)
            .updating($pressedKoreanWordID) { _, state, _ in
                guard columnIndex == 2, hideKoreanMeaning, revealsHiddenKoreanWhilePressing else { return }
                state = word.id
            }
    }
}
