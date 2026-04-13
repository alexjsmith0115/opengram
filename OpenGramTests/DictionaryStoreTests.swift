import Testing
import Foundation
@testable import OpenGramLib

@Suite("DictionaryStore Tests")
struct DictionaryStoreTests {

    private func makeTempStore() -> (DictionaryStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenGramTests")
            .appendingPathComponent(UUID().uuidString)
        return (DictionaryStore(directoryURL: dir), dir)
    }

    // MARK: - GRAM-07: Round-trip persistence

    @Test("saveWords then loadWords returns same words sorted")
    func roundTripPersistence() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.saveWords(["charlie", "alpha", "bravo"])
        let loaded = store.loadWords()
        #expect(loaded == ["alpha", "bravo", "charlie"])
    }

    @Test("dictionary file exists after saveWords")
    func fileExistsAfterSave() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.saveWords(["test"])
        let filePath = dir.appendingPathComponent("dictionary.txt")
        #expect(FileManager.default.fileExists(atPath: filePath.path))
    }

    // MARK: - Empty file handling

    @Test("loadWords returns empty array when file does not exist")
    func loadFromNonexistentFile() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let words = store.loadWords()
        #expect(words.isEmpty)
    }

    // MARK: - Directory creation

    @Test("saveWords creates intermediate directories if needed")
    func createsDirectories() {
        let deepDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenGramTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nested")
            .appendingPathComponent("deep")
        let store = DictionaryStore(directoryURL: deepDir)
        defer { try? FileManager.default.removeItem(at: deepDir.deletingLastPathComponent().deletingLastPathComponent()) }

        store.saveWords(["test"])
        let loaded = store.loadWords()
        #expect(loaded == ["test"])
    }

    @Test("overwriting existing dictionary replaces content")
    func overwriteExisting() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.saveWords(["first", "second"])
        store.saveWords(["only"])
        let loaded = store.loadWords()
        #expect(loaded == ["only"])
    }
}
