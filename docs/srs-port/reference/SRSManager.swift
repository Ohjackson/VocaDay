//
//  SRSManager.swift
//  tanngochou
//
//  Created by Jaehyun Ahn on 5/3/25.
//

import Foundation
import CoreData

private struct SRSProgressHighWaterValue: Codable {
    var stage: Int16
    var nextLearningDay: Int64
    var idkCount: Int16

    func merged(
        stage: Int16,
        nextLearningDay: Int64,
        idkCount: Int16
    ) -> SRSProgressHighWaterValue {
        SRSProgressHighWaterValue(
            stage: max(self.stage, stage),
            nextLearningDay: max(self.nextLearningDay, nextLearningDay),
            idkCount: max(self.idkCount, idkCount)
        )
    }
}

enum SRSProgressHighWaterStore {
    private static let storageKey = "srsProgressHighWaterV1"
    private static let lock = NSLock()

    static func record(_ cards: [SRSCard]) {
        lock.lock()
        defer { lock.unlock() }

        var stored = load()
        for card in cards {
            guard let wordID = card.word?.id?.uuidString else { continue }
            let current = stored[wordID] ?? SRSProgressHighWaterValue(
                stage: 0,
                nextLearningDay: 0,
                idkCount: 0
            )
            stored[wordID] = current.merged(
                stage: card.stage,
                nextLearningDay: card.nextLearningDay,
                idkCount: card.idkCount
            )
        }
        save(stored)
    }

    @discardableResult
    static func restoreMonotonicProgress(in cards: [SRSCard]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var stored = load()
        var changed = false

        for card in cards {
            guard let wordID = card.word?.id?.uuidString else { continue }
            let current = stored[wordID] ?? SRSProgressHighWaterValue(
                stage: 0,
                nextLearningDay: 0,
                idkCount: 0
            )
            let merged = current.merged(
                stage: card.stage,
                nextLearningDay: card.nextLearningDay,
                idkCount: card.idkCount
            )

            // stage는 오답 시 의도적으로 감소(강등)할 수 있으므로 과거 최고값으로
            // 되돌리지 않는다. nextLearningDay·idkCount만 기존처럼 역행을 방지한다.
            if card.nextLearningDay != merged.nextLearningDay {
                card.nextLearningDay = merged.nextLearningDay
                changed = true
            }
            if card.idkCount != merged.idkCount {
                card.idkCount = merged.idkCount
                changed = true
            }
            stored[wordID] = merged
        }

        save(stored)
        return changed
    }

    private static func load() -> [String: SRSProgressHighWaterValue] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode(
                  [String: SRSProgressHighWaterValue].self,
                  from: data
              ) else {
            return [:]
        }
        return values
    }

    private static func save(_ values: [String: SRSProgressHighWaterValue]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

final class SRSManager {
    static let shared = SRSManager()
    private let viewContext: NSManagedObjectContext
    // 1️⃣ 나중에 stage에 따라 다음 학습일을 계산할 때 사용할 간격 배열입니다.
    // 한자 단어장의 독립 SRS(KanjiBookManager)도 같은 간격표를 쓴다.
    static let baseGaps: [Int] = [0, 1, 1, 2, 2, 4, 7, 13, 30, 40, 50]
    private var BASE_GAPS: [Int] { Self.baseGaps }
    // 하루에 "오늘의 학습"으로 새로 편입되는 카드 수 상한. 며칠 안 켜서 밀린 카드가
    // 한꺼번에 쌓이거나 대량 시드/복원을 해도 세션이 무제한으로 커지지 않도록 막는다.
    private let dailyReviewLimit = 100

    private init() {
        viewContext = PersistenceController.shared.viewContext
    }

    // 2️⃣ 1차 학습(오늘의 학습) 단어를 가져오는 함수입니다.
    func fetchTodayWords(currentLearningDay: Int64) -> [Word] {
        // 3️⃣ 로직 2.1.3: SRSCard 엔티티를 조회하는 요청을 생성합니다.
        let request: NSFetchRequest<SRSCard> = SRSCard.fetchRequest()

        // 4️⃣ 'nextLearningDay'가 'currentLearningDay'보다 작거나 같은 모든 SRSCard를 찾는 조건을 설정합니다.
        request.predicate = NSPredicate(format: "nextLearningDay <= %lld", currentLearningDay)

        // 가장 많이 밀린 카드부터 우선 노출한다. nextLearningDay가 같으면(신규 단어는
        // 전부 0) 먼저 만든 단어를 앞세워 매번 순서가 들쭉날쭉해지는 걸 막는다.
        request.sortDescriptors = [
            NSSortDescriptor(key: "nextLearningDay", ascending: true),
            NSSortDescriptor(key: "word.date", ascending: true)
        ]
        // 하루 노출량 상한. 초과분은 그대로 대기하다 다음 조회 때 우선순위를 유지한 채
        // 자동으로 다시 걸린다 — 별도의 "롤오버" 로직이 필요 없다.
        request.fetchLimit = dailyReviewLimit

        do {
            // 5️⃣ 설정된 조건으로 Core Data에서 SRSCard들을 가져옵니다.
            let dueCards = try viewContext.fetch(request)
            
            // 6️⃣ 가져온 SRSCard들과 연결된(relationship) Word 객체들을 추출하여 배열로 반환합니다.
            //    'word'는 SRSCard 엔티티와 Word 엔티티의 관계(relationship) 이름입니다.
            let words = dueCards.compactMap { $0.word }
            return words
        } catch {
            // 7️⃣ 데이터 조회에 실패하면 에러를 출력하고 빈 배열을 반환합니다.
            print("Failed to fetch today's words: \(error)")
            return []
        }
    }
    
    // 8️⃣ 2차 학습(재도전) 단어를 가져오는 함수입니다.
    func fetchRetryWords(wordIDs: [String]) -> [Word] {
        // 9️⃣ 만약 재도전할 단어 ID 목록이 비어있으면, 즉시 빈 배열을 반환하여 불필요한 조회를 막습니다.
        guard !wordIDs.isEmpty else { return [] }
        
        // 1️⃣0️⃣ 문자열 배열(String Array)로 된 ID들을 UUID 객체 배열로 변환합니다.
        let wordUUIDs = wordIDs.compactMap { UUID(uuidString: $0) }
        
        // 1️⃣1️⃣ Word 엔티티를 조회하는 요청을 생성합니다.
        let request: NSFetchRequest<Word> = Word.fetchRequest()
        
        // 1️⃣2️⃣ 로직 2.3.2: 'id'가 변환된 UUID 목록에 포함된 모든 Word를 찾는 조건을 설정합니다.
        request.predicate = NSPredicate(format: "id IN %@", wordUUIDs)
        
        do {
            // 1️⃣3️⃣ 설정된 조건으로 Core Data에서 Word들을 가져와서 반환합니다.
            let words = try viewContext.fetch(request)
            return words
        } catch {
            // 1️⃣4️⃣ 데이터 조회에 실패하면 에러를 출력하고 빈 배열을 반환합니다.
            print("Failed to fetch retry words: \(error)")
            return []
        }
    }
    
    
    
    
    // 1️⃣ Word의 UUID를 이용해 연결된 SRSCard를 찾는 private 도우미 함수입니다.
        private func findSRSCard(for wordID: UUID) -> SRSCard? {
            let request: NSFetchRequest<Word> = Word.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", wordID as CVarArg)
            request.fetchLimit = 1
            
            do {
                let word = try viewContext.fetch(request).first
                return word?.srs // Word와 연결된 SRSCard 객체를 반환합니다.
            } catch {
                print("Failed to fetch Word with ID \(wordID): \(error)")
                return nil
            }
        }
    
    // 2️⃣ 로직 2.2.2: 1차 학습에서 '맞혔을 때' 호출되는 함수입니다.
       func markKnown(wordID: UUID, currentLearningDay: Int64) {
           guard let card = findSRSCard(for: wordID) else { return }
           
           // 3️⃣ stage를 1 증가시킵니다. BASE_GAPS 배열의 범위를 넘지 않도록 안전장치를 둡니다.
           let newStage = min(card.stage + 1, Int16(BASE_GAPS.count - 1))
           card.stage = newStage
           
           // 4️⃣ 새로운 다음 학습일을 공식에 따라 계산하고 저장합니다.
           card.nextLearningDay = currentLearningDay + Int64(BASE_GAPS[Int(newStage)])
       }
       
       // 5️⃣ 로직 2.2.2: 1차 학습에서 '틀렸을 때' 호출되는 함수입니다.
       func markWrong(wordID: UUID) {
           guard let card = findSRSCard(for: wordID) else { return }

           // 6️⃣ idkCount(틀린 횟수)를 1 증가시키고, stage를 한 단계 강등합니다(Leitner 방식).
           card.idkCount += 1
           card.stage = max(card.stage - 1, 0)
       }
       
       // 7️⃣ 로직 2.4.1: 2차(재도전) 학습에서 '맞혔을 때' 호출되는 함수입니다. 로직은 markKnown과 동일합니다.
       func retryMarkKnown(wordID: UUID, currentLearningDay: Int64) {
           markKnown(wordID: wordID, currentLearningDay: currentLearningDay)
       }
       
       // 8️⃣ 로직 2.4.1: 2차(재도전) 학습에서 '틀렸을 때' 호출되는 함수입니다.
       func retryMarkWrong(wordID: UUID, currentLearningDay: Int64) {
           guard let card = findSRSCard(for: wordID) else { return }

           // 9️⃣ idkCount를 올리고 stage를 강등한 뒤, 다음 학습일을 바로 다음 날(학습일+1)로 설정합니다.
           card.idkCount += 1
           card.stage = max(card.stage - 1, 0)
           card.nextLearningDay = currentLearningDay + 1
       }
       
       // 1️⃣0️⃣ 모든 변경사항을 Core Data에 최종 저장하는 함수입니다.
       @discardableResult
       func saveContext() -> Bool {
           do {
               try viewContext.save()
           } catch {
               viewContext.rollback()
               print("Error saving context: \(error)")
               return false
           }

           let request: NSFetchRequest<SRSCard> = SRSCard.fetchRequest()
           if let cards = try? viewContext.fetch(request) {
               SRSProgressHighWaterStore.record(cards)
           }
           return true
       }
}
