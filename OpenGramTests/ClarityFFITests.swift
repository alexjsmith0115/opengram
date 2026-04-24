import Testing
import Foundation
@testable import OpenGramLib

@Suite("Clarity FFI Surface")
struct ClarityFFITests {

    private func makeService(dialect: String = "US") -> HarperService {
        let store = DictionaryStore(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return HarperService(dictionaryStore: store, dialect: dialect)
    }

    @Test("FLAG_ME stub emits .clarity + .medium through full FFI stack")
    func stubRoundTrip() async {
        let service = makeService()
        let suggestions = await service.check(text: "FLAG_ME")
        let clarity = suggestions.filter { $0.category == .clarity }
        #expect(clarity.count == 1, "stub must emit exactly one clarity suggestion")
        #expect(clarity.first?.severity == .medium, "severity must round-trip as .medium")
        #expect(clarity.first?.primaryReplacement == "FLAGGED", "replacement must round-trip as FLAGGED")
    }
}
