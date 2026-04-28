import Testing
@testable import OpenGramLib

@Suite("RewriteTone")
struct RewriteToneTests {
    @Test("All cases iterable")
    func allCases() {
        #expect(RewriteTone.allCases == [.friendly, .professional, .simple])
    }

    @Test("Display names are user-readable")
    func displayNames() {
        #expect(RewriteTone.friendly.displayName == "Friendly")
        #expect(RewriteTone.professional.displayName == "Professional")
        #expect(RewriteTone.simple.displayName == "Simple")
    }

    @Test("Prompt instruction is non-empty and tone-specific")
    func promptInstruction() {
        #expect(RewriteTone.friendly.promptInstruction.localizedCaseInsensitiveContains("friendly"))
        #expect(RewriteTone.professional.promptInstruction.localizedCaseInsensitiveContains("professional"))
        #expect(RewriteTone.simple.promptInstruction.localizedCaseInsensitiveContains("simple"))
    }

    @Test("Raw values are stable for UserDefaults persistence")
    func rawValues() {
        #expect(RewriteTone.friendly.rawValue == "friendly")
        #expect(RewriteTone.professional.rawValue == "professional")
        #expect(RewriteTone.simple.rawValue == "simple")
    }
}
