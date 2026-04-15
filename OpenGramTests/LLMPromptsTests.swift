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
