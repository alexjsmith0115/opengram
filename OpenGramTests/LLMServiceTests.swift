import Testing
import Foundation
@testable import OpenGramLib

struct LLMServiceTests {

    // MARK: - JSON Parsing

    @Test func parseCleanJSONArray() async {
        let service = LLMService()
        let json = """
        [{"original": "I think", "replacement": "Consider", "reason": "hedging", "category": "tone"}]
        """
        let dtos = await service.parseJSONContent(json)
        #expect(dtos.count == 1)
        #expect(dtos[0].original == "I think")
        #expect(dtos[0].replacement == "Consider")
    }

    @Test func parseMarkdownFencedJSON() async {
        let service = LLMService()
        let json = """
        ```json
        [{"original": "sort of", "replacement": "somewhat", "reason": "hedging", "category": "tone"}]
        ```
        """
        let dtos = await service.parseJSONContent(json)
        #expect(dtos.count == 1)
        #expect(dtos[0].original == "sort of")
    }

    @Test func parsePreambleBeforeArray() async {
        let service = LLMService()
        let json = """
        Here are the suggestions:
        [{"original": "in order to", "replacement": "to", "reason": "wordiness", "category": "clarity"}]
        """
        let dtos = await service.parseJSONContent(json)
        #expect(dtos.count == 1)
        #expect(dtos[0].original == "in order to")
    }

    @Test func parseBrokenArrayFallsBackToBraceMatching() async {
        let service = LLMService()
        let json = """
        [{"original": "maybe", "replacement": "perhaps", "reason": "tone", "category": "tone"},
        broken stuff here
        {"original": "sort of", "replacement": "rather", "reason": "tone", "category": "tone"}]
        """
        let dtos = await service.parseJSONContent(json)
        #expect(dtos.count == 2)
    }

    @Test func parseCompleteGarbageReturnsEmpty() async {
        let service = LLMService()
        let dtos = await service.parseJSONContent("This is not JSON at all. No brackets.")
        #expect(dtos.isEmpty)
    }

    @Test func parseEmptyStringReturnsEmpty() async {
        let service = LLMService()
        let dtos = await service.parseJSONContent("")
        #expect(dtos.isEmpty)
    }

    // MARK: - LLMConfig

    @Test func configDefaultValues() {
        let config = LLMConfig.default
        #expect(config.baseURL == "http://localhost:1234/v1")
        #expect(config.temperature == 0.3)
        #expect(config.maxTokens == 1024)
        #expect(config.enabledChecks.count == 3)
        #expect(config.enabledChecks.contains(.tone))
        #expect(config.enabledChecks.contains(.clarity))
        #expect(config.enabledChecks.contains(.rephrase))
    }

    @Test func configIsEnabledFalseWhenURLEmpty() {
        var config = LLMConfig.default
        config.baseURL = ""
        #expect(!config.isEnabled)
    }

    @Test func configIsEnabledFalseWhenNoChecks() {
        var config = LLMConfig.default
        config.enabledChecks = []
        #expect(!config.isEnabled)
    }

    @Test func configChatCompletionsURL() {
        let config = LLMConfig.default
        #expect(config.chatCompletionsURL?.absoluteString == "http://localhost:1234/v1/chat/completions")
    }

    @Test func configChatCompletionsURLStripsTrailingSlash() {
        var config = LLMConfig.default
        config.baseURL = "http://localhost:1234/v1/"
        #expect(config.chatCompletionsURL?.absoluteString == "http://localhost:1234/v1/chat/completions")
    }
}
