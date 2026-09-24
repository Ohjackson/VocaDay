import SwiftData

extension ModelContext {
    @discardableResult
    func saveReportingError() -> Error? {
        do {
            try save()
            return nil
        } catch {
            return error
        }
    }
}
