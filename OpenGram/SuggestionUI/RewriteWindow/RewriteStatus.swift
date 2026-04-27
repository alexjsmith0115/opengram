import Foundation

enum RewriteStatus: Equatable {
    case idle
    case loading
    case done
    case error(RewriteError, attemptedTone: RewriteTone?)
}

enum RewriteError: LocalizedError, Equatable {
    case noAPIKey
    case llmFailed(String)
    case targetUnavailable
    case targetChanged
    case writeFailed(bundleID: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Configure LLM in Settings to use rewrite."
        case .llmFailed(let message):
            return "Rewrite failed: \(message)"
        case .targetUnavailable:
            return "Original text source no longer available. Cancel and reselect."
        case .targetChanged:
            return "Text changed since you opened this window. Cancel and reselect."
        case .writeFailed(let bundleID):
            return "Couldn't replace text in \(bundleID). Copy revised manually."
        }
    }
}
