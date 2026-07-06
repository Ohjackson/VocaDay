import SwiftUI

struct WordDataTable: View {
    let title: String
    let words: [VocaWord]
    var hideKoreanMeaning = false
    var allowsSelection = false
    var showsTitle = true
    @Binding var selectedWordIDs: Set<UUID>

    private let columns: [(title: String, width: CGFloat)] = [
        ("#", 56),
        ("English", 240),
        ("Korean Meaning", 300),
        ("Count", 90)
    ]

    var body: some View {
        #if os(iOS)
        iOSTable
        #else
        macTable
        #endif
    }

    #if os(iOS)
    private var iOSTable: some View {
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
                    title: "No saved words in this Day.",
                    systemImage: "text.page"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else {
                GeometryReader { proxy in
                    let widths = columnWidths(totalWidth: proxy.size.width)

                    VStack(spacing: 0) {
                        proportionalRow(
                            values: ["#", "English", "Korean Meaning"],
                            widths: widths,
                            isHeader: true
                        )

                        Divider()

                        ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                            proportionalRow(
                                values: [
                                    "\(index + 1)",
                                    word.english,
                                    hideKoreanMeaning ? "••••" : display(word.meaningKo)
                                ],
                                count: word.wrongCount,
                                widths: widths,
                                isHeader: false,
                                isSelected: selectedWordIDs.contains(word.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard allowsSelection else { return }
                                if selectedWordIDs.contains(word.id) {
                                    selectedWordIDs.remove(word.id)
                                } else {
                                    selectedWordIDs.insert(word.id)
                                }
                            }
                            Divider()
                        }
                    }
                }
                .frame(height: CGFloat(words.count + 1) * 45)
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

    private func cell(value: String, count: Int?, index: Int, isHeader: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(value)
                .font(isHeader ? .caption.weight(.semibold) : compactFont(for: index, value: value))
                .minimumScaleFactor(0.45)
                .foregroundStyle(isHeader ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
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
    #endif

    #if os(macOS)
    private var macTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Text("\(words.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if words.isEmpty {
                EmptyStateView(
                    title: "No saved words in this Day.",
                    systemImage: "text.page"
                )
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        tableRow(values: columns.map(\.title), isHeader: true)

                        Divider()

                        ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                            tableRow(
                                values: [
                                    "\(index + 1)",
                                    word.english,
                                    hideKoreanMeaning ? "••••" : display(word.meaningKo),
                                    "\(word.wrongCount)"
                                ],
                                isHeader: false,
                                isSelected: selectedWordIDs.contains(word.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard allowsSelection else { return }
                                if selectedWordIDs.contains(word.id) {
                                    selectedWordIDs.remove(word.id)
                                } else {
                                    selectedWordIDs.insert(word.id)
                                }
                            }
                            Divider()
                        }
                    }
                    .frame(minWidth: columns.reduce(0) { $0 + $1.width }, alignment: .leading)
                }
            }
        }
        .padding(18)
        .calmCard()
    }
    #endif

    private func tableRow(values: [String], isHeader: Bool, isSelected: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(isHeader ? .subheadline.weight(.semibold) : .body)
                    .font(index == 3 && !isHeader ? .caption.monospacedDigit() : nil)
                    .foregroundStyle(isHeader ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(width: columns[index].width, alignment: index == 0 || index == 3 ? .center : .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
            }
        }
        .background(rowBackground(isHeader: isHeader, isSelected: isSelected))
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
}
