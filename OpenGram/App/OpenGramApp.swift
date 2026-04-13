import Foundation

enum AppState: String, Sendable {
    case idle
    case checking
    case done

    var imageName: String {
        switch self {
        case .idle: return "StatusIdle"
        case .checking: return "StatusChecking"
        case .done: return "StatusIdle"
        }
    }
}
