import Foundation

enum LLMPrompts {
    /// Returns the system prompt for the given check type.
    /// `harperSpans` are text fragments already flagged by the grammar checker --
    /// the LLM must skip these to avoid duplicate suggestions (D-11, LLM-02, LLM-03).
    static func systemPrompt(for type: LLMCheckType, harperSpans: [String]) -> String {
        let spanClause: String
        if harperSpans.isEmpty {
            spanClause = ""
        } else {
            let quoted = harperSpans.map { "\"\($0)\"" }.joined(separator: ", ")
            spanClause = "\nThe grammar checker already flagged these spans: [\(quoted)]. Do NOT suggest changes for any of these spans."
        }

        switch type {
        case .tone:
            return """
            You are a writing tone analyzer. Identify hedging language ("I think", "sort of", \
            "maybe", "might"), unnecessary qualifiers, and passive voice where active would be \
            stronger. Suggest more confident, direct alternatives.\(spanClause)

            Do NOT flag grammar, spelling, or punctuation issues.

            Respond with ONLY a JSON array. No markdown, no preamble, no explanation outside the JSON.
            Each element: {"original": "exact text from input", "replacement": "improved text", \
            "reason": "brief explanation", "category": "tone"}
            Return [] if no suggestions apply.

            Example: [{"original": "I think we should", "replacement": "We should", \
            "reason": "Remove hedging for directness", "category": "tone"}]
            """
        case .clarity:
            return """
            You are a writing clarity analyzer. Identify wordiness, redundant phrases, overly \
            complex sentence structure, and nominalizations that could be verbs. Suggest tighter, \
            clearer phrasing.\(spanClause)

            Do NOT flag grammar, spelling, or punctuation issues.

            Respond with ONLY a JSON array. No markdown, no preamble, no explanation outside the JSON.
            Each element: {"original": "exact text from input", "replacement": "improved text", \
            "reason": "brief explanation", "category": "clarity"}
            Return [] if no suggestions apply.

            Example: [{"original": "in order to achieve", "replacement": "to achieve", \
            "reason": "Remove redundant phrasing", "category": "clarity"}]
            """
        case .rephrase:
            return """
            You are a writing style improver. Given text, suggest restructured versions that \
            improve flow and directness. Preserve the original meaning but you may significantly \
            change sentence structure.\(spanClause)

            Do NOT flag grammar, spelling, or punctuation issues.

            Respond with ONLY a JSON array. No markdown, no preamble, no explanation outside the JSON.
            Each element: {"original": "exact text from input", "replacement": "improved text", \
            "reason": "brief explanation", "category": "rephrase"}
            Return [] if no suggestions apply.

            Example: [{"original": "The report was written by the team and it was submitted on Friday", \
            "replacement": "The team wrote and submitted the report on Friday", \
            "reason": "Active voice improves directness", "category": "rephrase"}]
            """
        }
    }
}
