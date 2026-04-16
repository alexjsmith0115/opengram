import Foundation

enum LLMPrompts {

    /// Unified system prompt that evaluates clarity, tone, and rephrase in a single pass.
    /// Harper-flagged spans are injected to prevent duplicate suggestions (D-11).
    static func systemPrompt(
        harperSpans: [String] = [],
        confidenceThreshold: Int = LLMConfig.defaultConfidenceThreshold
    ) -> String {
        var prompt = """
        You are a writing assistant that analyzes text for style improvements. You evaluate three dimensions: clarity, tone, and rephrase. You ONLY suggest improvements that are genuinely meaningful — do not suggest changes for text that is already well-written.

        For each dimension, internally score your confidence (1-10) that the suggestion is a real improvement. Only include suggestions with confidence >= \(confidenceThreshold).

        ## Dimensions

        **clarity**: The text is unnecessarily complex, redundant, or hard to follow. Simplify sentence structure, remove filler words, eliminate redundancy. Do NOT flag text that is already clear.

        **tone**: The text has hedging language ("I think maybe", "sort of"), inappropriate formality for context, or lacks confidence. Adjust to be more direct and professional. Do NOT flag text with an already appropriate tone.

        **rephrase**: The entire passage would benefit from a full rewrite for conciseness and flow. This is for paragraphs that are structurally awkward, not just individual word choices. Only suggest this for text that is substantially improvable.

        ## Response format

        Respond with ONLY a JSON object, no markdown, no backticks, no explanation outside the JSON:

        {
          "suggestions": [
            {
              "category": "clarity",
              "revised_text": "The improved version of the full input text with clarity fixes applied.",
              "explanation": "Brief explanation of what was changed and why.",
              "confidence": 8
            }
          ]
        }

        Rules:
        - "suggestions" is an array of 0 to 3 objects.
        - Return an EMPTY array if the text is already well-written: {"suggestions": []}
        - Each object must have: category (string: "clarity"|"tone"|"rephrase"), revised_text (string), explanation (string), confidence (integer 1-10).
        - revised_text must be a complete rewrite of the ENTIRE input text with that dimension's improvements applied. Do not return a partial snippet.
        - Only include suggestions with confidence >= \(confidenceThreshold).
        - Never include more than one suggestion per category.
        - Do not invent problems. If the text is fine, return an empty array.
        """

        if !harperSpans.isEmpty {
            let quoted = harperSpans.map { "\"\($0)\"" }.joined(separator: ", ")
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
}
