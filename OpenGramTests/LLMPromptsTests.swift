import Testing
@testable import OpenGramLib

struct LLMPromptsTests {

    @Test func promptIsNonEmpty() {
        let prompt = LLMPrompts.systemPrompt()
        #expect(!prompt.isEmpty)
    }

    @Test func promptCoversAllThreeDimensions() {
        let prompt = LLMPrompts.systemPrompt()
        #expect(prompt.contains("clarity"))
        #expect(prompt.contains("tone"))
        #expect(prompt.contains("rephrase"))
    }

    @Test func promptRequestsJSONObject() {
        let prompt = LLMPrompts.systemPrompt()
        #expect(prompt.contains("\"suggestions\""))
    }

    @Test func promptIncludesHarperSpans() {
        let prompt = LLMPrompts.systemPrompt(harperSpans: ["teh", "recieve"])
        #expect(prompt.contains("\"teh\""))
        #expect(prompt.contains("\"recieve\""))
        #expect(prompt.contains("grammar checker already flagged"))
    }

    @Test func promptExcludesSpanClauseWhenEmpty() {
        let prompt = LLMPrompts.systemPrompt(harperSpans: [])
        #expect(!prompt.contains("grammar checker already flagged"))
    }

    @Test func userMessageFormatsCorrectly() {
        let msg = LLMPrompts.userMessage(for: "Hello world")
        #expect(msg == "Analyze this text:\n\nHello world")
    }
}

@Suite("LLMPromptsIncremental")
struct LLMPromptsIncrementalTests {

    @Test func bothContextsPresent() {
        let msg = LLMPrompts.userMessageIncremental(
            target: "T",
            previousContext: "P",
            nextContext: "N"
        )
        #expect(msg.contains("Previous paragraph (context only, do not suggest changes):"))
        #expect(msg.contains("Target paragraph (provide suggestions for this paragraph only):"))
        #expect(msg.contains("Following paragraph (context only, do not suggest changes):"))
        #expect(msg.contains("\nP\n"))
        #expect(msg.contains("\nT\n"))
        #expect(msg.contains("\nN"))
    }

    @Test func previousNil() {
        let msg = LLMPrompts.userMessageIncremental(
            target: "T",
            previousContext: nil,
            nextContext: "N"
        )
        guard let prevLabelRange = msg.range(of: "Previous paragraph (context only, do not suggest changes):\n") else {
            Issue.record("Previous label missing")
            return
        }
        let afterLabel = msg[prevLabelRange.upperBound...]
        #expect(afterLabel.hasPrefix("<none>"))
    }

    @Test func nextNil() {
        let msg = LLMPrompts.userMessageIncremental(
            target: "T",
            previousContext: "P",
            nextContext: nil
        )
        guard let nextLabelRange = msg.range(of: "Following paragraph (context only, do not suggest changes):\n") else {
            Issue.record("Following label missing")
            return
        }
        let afterLabel = msg[nextLabelRange.upperBound...]
        #expect(afterLabel.hasPrefix("<none>"))
    }

    @Test func bothNil() {
        let msg = LLMPrompts.userMessageIncremental(
            target: "Target body verbatim.",
            previousContext: nil,
            nextContext: nil
        )
        #expect(msg.contains("Previous paragraph (context only, do not suggest changes):\n<none>"))
        #expect(msg.contains("Following paragraph (context only, do not suggest changes):\n<none>"))
        #expect(msg.contains("Target paragraph (provide suggestions for this paragraph only):\nTarget body verbatim."))
    }

    @Test func labelOrdering() {
        let msg = LLMPrompts.userMessageIncremental(
            target: "T",
            previousContext: "P",
            nextContext: "N"
        )
        let prevIdx = msg.range(of: "Previous paragraph")!.lowerBound
        let targetIdx = msg.range(of: "Target paragraph")!.lowerBound
        let followingIdx = msg.range(of: "Following paragraph")!.lowerBound
        #expect(prevIdx < targetIdx)
        #expect(targetIdx < followingIdx)
    }

    @Test func targetInsertedVerbatim() {
        let raw = "  leading and trailing  "
        let msg = LLMPrompts.userMessageIncremental(
            target: raw,
            previousContext: nil,
            nextContext: nil
        )
        #expect(msg.contains(raw))
    }
}
