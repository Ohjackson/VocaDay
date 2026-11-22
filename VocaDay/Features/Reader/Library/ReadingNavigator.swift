import Foundation

/// 책 안에서 문장 위치를 앞뒤로 옮기는 규칙. 화면과 재생이 같이 쓴다.
nonisolated struct ReadingNavigator: Sendable {
    let positions: [ReadingPosition]
    private let indexByPosition: [ReadingPosition: Int]

    init(book: BookDocument) {
        self.init(positions: book.positions)
    }

    init(positions: [ReadingPosition]) {
        self.positions = positions
        var map: [ReadingPosition: Int] = [:]
        for (index, position) in positions.enumerated() {
            map[position] = index
        }
        indexByPosition = map
    }

    var count: Int { positions.count }

    func index(of position: ReadingPosition) -> Int? {
        indexByPosition[position]
    }

    func next(after position: ReadingPosition) -> ReadingPosition? {
        guard let index = index(of: resolve(position)), positions.indices.contains(index + 1) else { return nil }
        return positions[index + 1]
    }

    func previous(before position: ReadingPosition) -> ReadingPosition? {
        guard let index = index(of: resolve(position)), index > 0 else { return nil }
        return positions[index - 1]
    }

    /// 저장된 위치를 이 책의 실제 문장으로 맞춘다. 책 내용이 바뀌어 없는 위치면 그 앞의 가장 가까운 문장으로 간다.
    func resolve(_ saved: ReadingPosition?) -> ReadingPosition {
        guard let first = positions.first else { return .start }
        guard let saved else { return first }
        if indexByPosition[saved] != nil { return saved }
        return positions.last { $0 < saved } ?? first
    }

    /// 1부터 세는 문장 번호. 재생 막대의 "3 / 40" 에 쓴다.
    func ordinal(of position: ReadingPosition) -> Int {
        (index(of: resolve(position)) ?? 0) + 1
    }

    /// 0...1. 책 목록의 진행 표시에 쓴다.
    func progress(of position: ReadingPosition) -> Double {
        guard count > 1 else { return count == 1 ? 1 : 0 }
        return Double(ordinal(of: position) - 1) / Double(count - 1)
    }

    /// 장마다 첫 문장. 목차에 쓴다. 문장이 없는 장은 빠진다.
    var chapterStarts: [ReadingPosition] {
        var seen = Set<Int>()
        return positions.filter { seen.insert($0.chapter).inserted }
    }

    /// 문단의 첫 문장.
    func firstPosition(chapter: Int, paragraph: Int) -> ReadingPosition? {
        positions.first { $0.chapter == chapter && $0.paragraph == paragraph }
    }
}
