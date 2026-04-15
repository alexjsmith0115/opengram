import Testing
@testable import OpenGramLib

struct LLMPromptsTests {

    @Test(arguments: LLMCheckType.allCases)
    func promptIsNonEmpty(type: LLMCheckType) {
        let prompt = LLMPrompts.systemPrompt(for: type, harperSpans: [])
        #expect(!prompt.isEmpty)
    }

    @Test(arguments: LLMCheckType.allCases)
    func promptSkipsGrammar(type: LLMCheckType) {
        let prompt = LLMPrompts.systemPrompt(for: type, harperSpans: [])
        #expect(prompt.contains("Do NOT flag grammar, spelling, or punctuation"))
    }

    @Test(arguments: LLMCheckType.allCases)
    func promptRequestsJSONOnly(type: LLMCheckType) {
        let prompt = LLMPrompts.systemPrompt(for: type, harperSpans: [])
        #expect(prompt.contains("Respond with ONLY a JSON array"))
    }

    @Test func promptIncludesHarperSpans() {
        let prompt = LLMPrompts.systemPrompt(for: .tone, harperSpans: ["teh", "recieve"])
        #expect(prompt.contains("\"teh\""))
        #expect(prompt.contains("\"recieve\""))
        #expect(prompt.contains("grammar checker already flagged"))
    }

    @Test func promptExcludesSpanClauseWhenEmpty() {
        let prompt = LLMPrompts.systemPrompt(for: .tone, harperSpans: [])
        #expect(!prompt.contains("grammar checker already flagged"))
    }
}
