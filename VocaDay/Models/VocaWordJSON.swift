import Foundation

struct VocaWordJSON: Codable, Identifiable, Hashable {
    var id: UUID
    var english: String
    var meaningKo: String
    var exampleEn: String
    var exampleKo: String
    var note: String
    var toeicTag: String

    init(
        id: UUID = UUID(),
        english: String,
        meaningKo: String = "",
        exampleEn: String = "",
        exampleKo: String = "",
        note: String = "",
        toeicTag: String = ""
    ) {
        self.id = id
        self.english = english
        self.meaningKo = meaningKo
        self.exampleEn = exampleEn
        self.exampleKo = exampleKo
        self.note = note
        self.toeicTag = toeicTag
    }

    enum CodingKeys: String, CodingKey {
        case id
        case english
        case meaningKo
        case exampleEn
        case exampleKo
        case note
        case partOfSpeech
        case toeicTag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        english = try container.decodeIfPresent(String.self, forKey: .english) ?? ""
        meaningKo = try container.decodeIfPresent(String.self, forKey: .meaningKo) ?? ""
        exampleEn = try container.decodeIfPresent(String.self, forKey: .exampleEn) ?? ""
        exampleKo = try container.decodeIfPresent(String.self, forKey: .exampleKo) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note)
            ?? container.decodeIfPresent(String.self, forKey: .partOfSpeech)
            ?? ""
        toeicTag = try container.decodeIfPresent(String.self, forKey: .toeicTag) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(english, forKey: .english)
        try container.encode(meaningKo, forKey: .meaningKo)
        try container.encode(exampleEn, forKey: .exampleEn)
        try container.encode(exampleKo, forKey: .exampleKo)
        try container.encode(note, forKey: .note)
        try container.encode(toeicTag, forKey: .toeicTag)
    }
}
