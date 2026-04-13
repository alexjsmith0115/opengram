import Foundation

protocol DictionaryStoreProtocol: Sendable {
    func loadWords() -> [String]
    func saveWords(_ words: [String])
}

struct DictionaryStore: DictionaryStoreProtocol, Sendable {

    private let directoryURL: URL
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.directoryURL = appSupport.appendingPathComponent("OpenGram")
        self.fileURL = directoryURL.appendingPathComponent("dictionary.txt")
    }

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent("dictionary.txt")
    }

    func loadWords() -> [String] {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        return contents
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }

    func saveWords(_ words: [String]) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let sorted = words.sorted()
            let contents = sorted.joined(separator: "\n")
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            // D-11: Phase 2 is pipeline-only. Log count, not content.
            print("DictionaryStore: failed to save \(words.count) words: \(error.localizedDescription)")
        }
    }
}
