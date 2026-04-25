import Testing
import Foundation
@testable import OpenGramLib

@Suite("Clarity FFI Surface")
struct ClarityFFITests {

    private func makeService(dialect: String = "US") -> HarperService {
        let store = DictionaryStore(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return HarperService(dictionaryStore: store, dialect: dialect)
    }

    @Test("WordyPhrasesLinter emits .clarity + .high through full FFI stack")
    func utilizeRoundTrip() async {
        let service = makeService()
        let suggestions = await service.check(text: "Please utilize this.")
        let clarity = suggestions.filter { $0.category == .clarity && $0.primaryReplacement == "use" }
        #expect(clarity.count == 1, "WordyPhrasesLinter must emit exactly one clarity suggestion for 'utilize'")
        #expect(clarity.first?.severity == .high, "severity must round-trip as .high (CORPUS: utilize → Severity::High)")
        #expect(clarity.first?.primaryReplacement == "use", "replacement must round-trip as 'use'")
    }
}
