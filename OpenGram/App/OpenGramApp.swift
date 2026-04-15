import Foundation

enum AppState: String, Sendable {
    case idle
    case checking
    case checkingLLM
    case done

    var sfSymbolName: String {
        switch self {
        case .idle: return "checkmark.circle"
        case .checking: return "checkmark.circle.fill"
        case .checkingLLM: return "checkmark.circle.fill"
        case .done: return "checkmark.circle"
        }
    }
}
