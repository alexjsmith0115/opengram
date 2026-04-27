import Foundation

enum LLMPrompts {

    /// Unified system prompt that evaluates tone, rephrase, and grammar/spelling in a single pass.
    /// Harper-flagged spans are injected to prevent duplicate suggestions.
    static func systemPrompt(
        harperSpans: [String] = [],
        confidenceThreshold: Int = LLMConfig.defaultConfidenceThreshold
    ) -> String {
        var prompt = """
        You are a writing assistant that analyzes text for style, grammar, and spelling improvements. You evaluate three dimensions: tone, rephrase, and grammar/spelling. You ONLY suggest improvements that are genuinely meaningful — do not suggest changes for text that is already well-written.

        For each dimension, internally score your confidence (1-10) that the suggestion is a real improvement. Only include suggestions with confidence >= \(confidenceThreshold). Use 9-10 only for substantial, objective improvements that most readers would prefer. Treat merely acceptable, optional, stylistic, or taste-based rewrites as 8 or below and omit them.

        ## Dimensions

        **tone**: The text has hedging language ("I think maybe", "sort of"), inappropriate formality for context, or lacks confidence. Adjust to be more direct and professional. Do NOT flag text with an already appropriate tone.

        **rephrase**: The entire passage would benefit from a full rewrite for conciseness and flow. This is for paragraphs that are structurally awkward, not just individual word choices. Only suggest this for text that is substantially improvable.

        Note: grammar errors and spelling mistakes may also be present. When composing a rephrase suggestion, fix any grammar or spelling issues in the revised text as part of the overall improvement (REPH-11 superset: the rephrase is a Harper superset).

        ## Response format

        Respond with ONLY a JSON object, no markdown, no backticks, no explanation outside the JSON:

        {
          "suggestions": [
            {
              "category": "tone",
              "revised_text": "The improved version of the full input text with tone fixes applied.",
              "explanation": "Brief explanation of what was changed and why.",
              "confidence": \(confidenceThreshold)
            }
          ]
        }

        Rules:
        - "suggestions" is an array of 0 to 2 objects.
        - Return an EMPTY array if the text is already well-written: {"suggestions": []}
        - Each object must have: category (string: "tone"|"rephrase"), revised_text (string), explanation (string), confidence (integer 1-10).
        - revised_text must be a complete rewrite of the ENTIRE input text with that dimension's improvements applied. Do not return a partial snippet.
        - Only include suggestions with confidence >= \(confidenceThreshold).
        - Never include more than one suggestion per category.
        - Do not invent problems. If the text is fine, return an empty array.
        - Do not suggest changes for clear casual updates, list items, test sentences, or already fluent paragraphs unless there is a concrete writing problem.
        """

        if !harperSpans.isEmpty {
            let quoted = harperSpans.map { span in
                let escaped = span
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }.joined(separator: ", ")
            prompt += "\n\nThe grammar checker already flagged these spans: [\(quoted)]. Do NOT suggest changes for any of these spans."
        }

        return prompt
    }

    /// Formats the user message for the chat completion request.
    static func userMessage(for paragraph: String) -> String {
        "Analyze this text:\n\n\(paragraph)"
    }

    /// Incremental user message with labeled previous/target/next sections (D-05).
    /// Missing neighbors are rendered as literal "<none>" so the prompt structure
    /// stays invariant whether or not context paragraphs exist.
    static func userMessageIncremental(target: String, previousContext: String?, nextContext: String?) -> String {
        let prev = previousContext ?? "<none>"
        let next = nextContext ?? "<none>"
        return """
        Previous paragraph (context only, do not suggest changes):
        \(prev)

        Target paragraph (provide suggestions for this paragraph only):
        \(target)

        Following paragraph (context only, do not suggest changes):
        \(next)
        """
    }

    // MARK: - Rewrite

    static func rewriteSystemPrompt(tone: RewriteTone) -> String {
        """
        \(tone.promptInstruction)
        Preserve paragraph breaks from the input.
        Output ONLY the rewritten text — no preamble, no quotes, no commentary.
        """
    }

    static func rewriteUserMessage(text: String) -> String {
        text
    }
}
