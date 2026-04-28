import Foundation

enum RewriteTone: String, CaseIterable, Sendable, Codable, Equatable {
    case friendly
    case professional
    case simple

    var displayName: String {
        switch self {
        case .friendly:     return "Friendly"
        case .professional: return "Professional"
        case .simple:       return "Simple"
        }
    }

    var promptInstruction: String {
        switch self {
        case .friendly:
            return "Rewrite the user's text in a more friendly, warm, conversational tone."
        case .professional:
            return "Rewrite the user's text in a more professional, formal, polished tone."
        case .simple:
            return "Rewrite the user's text in a simpler, plainer style: shorter sentences, common words, no jargon."
        }
    }
}
