import Foundation

struct VocaAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension VocaAlert {
    static func saveFailure(_ error: Error) -> VocaAlert {
        VocaAlert(title: "저장 실패", message: error.localizedDescription)
    }
}
