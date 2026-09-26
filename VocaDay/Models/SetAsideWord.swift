import Foundation
import SwiftData

/// 기본 단어장 검수에서 "이미 알아요"로 뺀 단어. 데이에는 넣지 않고 다음 후보에서도 제외한다.
/// 삭제(되돌리기)하면 다시 후보가 된다. 기기마다 같은 단어가 생겨도 영어 철자 기준으로 한 번만 센다.
@Model
final class SetAsideWord {
    var id: UUID = UUID()
    var english: String = ""
    var meaningKo: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), english: String, meaningKo: String = "", createdAt: Date = Date()) {
        self.id = id
        self.english = english
        self.meaningKo = meaningKo
        self.createdAt = createdAt
    }
}
