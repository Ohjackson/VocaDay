import Foundation

enum ReviewDecision: String, Equatable {
    case again
    case known
}

/// 카드 복습 한 판의 진행 상태입니다. 화면과 분리해 테스트할 수 있게 둡니다.
///
/// 불변식: `currentIndex` 앞의 카드는 모두 판단됐고, 그 뒤의 카드는 판단되지 않았습니다.
struct ReviewDeck: Equatable {
    private(set) var wordIDs: [UUID]
    private(set) var currentIndex = 0
    private(set) var decisions: [UUID: ReviewDecision] = [:]

    init(wordIDs: [UUID] = []) {
        self.wordIDs = wordIDs
    }

    var currentWordID: UUID? {
        wordIDs.indices.contains(currentIndex) ? wordIDs[currentIndex] : nil
    }

    var isEmpty: Bool { wordIDs.isEmpty }
    var isComplete: Bool { !wordIDs.isEmpty && currentIndex >= wordIDs.count }
    var canGoBack: Bool { currentIndex > 0 }
    var decidedCount: Int { currentIndex }

    func count(of decision: ReviewDecision) -> Int {
        decisions.values.filter { $0 == decision }.count
    }

    mutating func decide(_ decision: ReviewDecision) {
        guard let id = currentWordID else { return }
        decisions[id] = decision
        currentIndex += 1
    }

    mutating func goBack() {
        guard canGoBack else { return }
        currentIndex -= 1
        decisions[wordIDs[currentIndex]] = nil
    }

    /// 판단하지 않은 카드만 섞습니다. 이미 판단한 카드의 순서는 유지합니다.
    mutating func shuffleRemaining<G: RandomNumberGenerator>(using generator: inout G) {
        wordIDs = Array(wordIDs[..<currentIndex]) + wordIDs[currentIndex...].shuffled(using: &generator)
    }

    mutating func shuffleRemaining() {
        var generator = SystemRandomNumberGenerator()
        shuffleRemaining(using: &generator)
    }

    /// 단어가 추가·삭제됐을 때 순서와 판단을 맞춥니다. 새 단어는 뒤에 붙습니다.
    mutating func sync(with availableIDs: [UUID]) {
        let available = Set(availableIDs)
        let kept = wordIDs.filter { available.contains($0) }
        let keptSet = Set(kept)
        wordIDs = kept + availableIDs.filter { !keptSet.contains($0) }
        decisions = decisions.filter { available.contains($0.key) }
        currentIndex = wordIDs.firstIndex { decisions[$0] == nil } ?? wordIDs.count
    }
}
