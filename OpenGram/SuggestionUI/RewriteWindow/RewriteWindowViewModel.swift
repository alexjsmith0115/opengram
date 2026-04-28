import Foundation
import Observation

protocol RewriteLLMProvider: Sendable {
    func rewrite(text: String, tone: RewriteTone) async throws -> String
}

protocol RewriteConfigProvider: Sendable {
    var llmConfig: LLMConfig { get }
    func currentAPIKey() -> String?
}

@MainActor
@Observable
final class RewriteWindowViewModel {
    private(set) var original: String
    var revised: String = ""
    private(set) var selectedTone: RewriteTone?
    private(set) var status: RewriteStatus = .idle

    private let llm: RewriteLLMProvider
    private let configManager: RewriteConfigProvider
    private var generationID: UInt64 = 0
    private var inFlight: Task<Void, Never>?

    var canApply: Bool {
        if case .done = status { return !revised.isEmpty }
        return false
    }

    init(original: String, llm: RewriteLLMProvider, configManager: RewriteConfigProvider) {
        self.original = original
        self.llm = llm
        self.configManager = configManager
    }

    /// Editing original invalidates any existing rewrite — user must re-select a tone.
    func updateOriginal(_ newText: String) {
        guard newText != original else { return }
        original = newText
        invalidateRewrite()
    }

    /// Surfaces AX-side errors (target unavailable / changed, write failed) without
    /// going through the tone-fire path.
    func setError(_ err: RewriteError, attemptedTone: RewriteTone?) {
        status = .error(err, attemptedTone: attemptedTone)
    }

    func selectTone(_ tone: RewriteTone) {
        inFlight?.cancel()
        generationID &+= 1
        let myID = generationID
        selectedTone = tone

        // No API-key gate: local LLMs (LM Studio / Ollama / similar) require no key.
        // Auth absence surfaces via HTTP 401 from servers that do require auth.
        status = .loading
        let llm = self.llm
        let original = self.original

        inFlight = Task { [weak self] in
            do {
                let result = try await llm.rewrite(text: original, tone: tone)
                guard let self, !Task.isCancelled, myID == self.generationID else { return }
                self.revised = result
                self.status = .done
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, myID == self.generationID else { return }
                self.status = .error(.llmFailed(error.localizedDescription), attemptedTone: tone)
            }
        }
    }

    func retry() {
        guard case .error(_, let attemptedTone) = status, let tone = attemptedTone else { return }
        selectTone(tone)
    }

    func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    private func invalidateRewrite() {
        inFlight?.cancel()
        inFlight = nil
        generationID &+= 1
        revised = ""
        selectedTone = nil
        status = .idle
    }

    /// Awaits the in-flight task for test synchronisation. No-op in production flows.
    func waitForCompletion() async {
        await inFlight?.value
    }
}
