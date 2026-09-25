import SwiftUI

/// 단어: 검색·정렬·필터로 단어별 학습 상태 보기.
struct StatsWordListSection: View {
    enum Sort: String, CaseIterable, Identifiable {
        case nextReview = "다음 복습 순"
        case hardest = "많이 틀린 순"
        case stageLow = "단계 낮은 순"
        case stageHigh = "단계 높은 순"
        case recent = "최근 추가 순"
        var id: Self { self }
    }

    let stats: StudyStats
    let history: ReviewHistoryStats
    let wordsByID: [UUID: VocaWord]

    @State private var query = ""
    @State private var sort: Sort = .nextReview
    @State private var bucket: StageBucket?
    @State private var dayID: UUID?
    @State private var enrichedOnly: Bool?

    private var filtered: [StatsWord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespaces).lowercased()
        let result = stats.words.filter { word in
            (normalizedQuery.isEmpty
                || word.term.lowercased().contains(normalizedQuery)
                || word.meaningKo.contains(normalizedQuery))
                && (bucket == nil || word.bucket == bucket)
                && (dayID == nil || word.dayID == dayID)
                && (enrichedOnly == nil || word.isEnriched == enrichedOnly)
        }
        switch sort {
        case .nextReview:
            return result.sorted { ($0.card.nextLearningDay, $0.createdAt) < ($1.card.nextLearningDay, $1.createdAt) }
        case .hardest:
            return result.sorted { ($0.card.idkCount, -$0.card.stage) > ($1.card.idkCount, -$1.card.stage) }
        case .stageLow:
            return result.sorted { ($0.card.stage, $0.createdAt) < ($1.card.stage, $1.createdAt) }
        case .stageHigh:
            return result.sorted { ($0.card.stage, $1.createdAt) > ($1.card.stage, $0.createdAt) }
        case .recent:
            return result.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        let words = filtered
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("단어나 뜻 검색", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            .padding(10)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("정렬", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { chip(sort.rawValue, systemImage: "arrow.up.arrow.down", isActive: true) }

                    Menu {
                        Button("전체 구간") { bucket = nil }
                        ForEach(StageBucket.allCases) { item in
                            Button(item.title) { bucket = item }
                        }
                    } label: { chip(bucket?.title ?? "전체 구간", systemImage: "square.stack.3d.up", isActive: bucket != nil) }

                    Menu {
                        Button("모든 데이") { dayID = nil }
                        ForEach(stats.dayBreakdowns) { day in
                            Button(day.title) { dayID = day.id }
                        }
                    } label: {
                        chip(stats.dayBreakdowns.first { $0.id == dayID }?.title ?? "모든 데이", systemImage: "calendar", isActive: dayID != nil)
                    }

                    Menu {
                        Button("전체") { enrichedOnly = nil }
                        Button("문제 준비됨") { enrichedOnly = true }
                        Button("준비 안 됨") { enrichedOnly = false }
                    } label: {
                        chip(enrichedOnly == nil ? "보강 전체" : (enrichedOnly! ? "문제 준비됨" : "준비 안 됨"), systemImage: "sparkles", isActive: enrichedOnly != nil)
                    }
                }
            }

            Text("\(words.count)개 단어")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVStack(spacing: 0) {
                ForEach(words) { word in
                    if let vocaWord = wordsByID[word.id] {
                        NavigationLink(value: AppRoute.wordStudyDetail(wordID: vocaWord.id)) {
                            StatsWordRow(word: word, stats: stats)
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .calmCard()
        }
    }

    private func chip(_ title: String, systemImage: String, isActive: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? Color.accentColor : .primary)
            .background(isActive ? Color.accentColor.opacity(0.12) : AppTheme.cardBackground, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.softStroke))
    }
}
