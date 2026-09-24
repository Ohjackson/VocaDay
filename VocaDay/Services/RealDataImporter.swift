import Foundation

enum RealDataImporterError: LocalizedError {
    case resourceNotFound

    var errorDescription: String? {
        switch self {
        case .resourceNotFound:
            "번들에 포함된 실제 데이터 파일을 찾을 수 없습니다."
        }
    }
}

enum RealDataImporter {
    static func loadArchive() throws -> AppDataArchive {
        guard let url = Bundle.main.url(forResource: "RealDataBackup", withExtension: "json") else {
            throw RealDataImporterError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AppDataBackupError.invalidFile
        }
        return try AppDataBackupService.decode(json)
    }
}
