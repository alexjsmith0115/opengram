import Testing
import Foundation
@testable import OpenGramLib

@Suite struct WithTimeoutTests {
    @Test func resolvesFastOperation() async throws {
        let result = try await withTimeout(seconds: 10) {
            try await Task.sleep(for: .milliseconds(5))
            return "ok"
        }
        #expect(result == "ok")
    }

    @Test func throwsTimeoutWhenOperationExceedsDeadline() async {
        do {
            _ = try await withTimeout(seconds: 0.05) {
                try await Task.sleep(for: .seconds(1))
                return "nope"
            }
            Issue.record("expected timeout")
        } catch is TimeoutError {
            // success
        } catch {
            Issue.record("expected TimeoutError, got \(error)")
        }
    }

    private struct StubOpError: Error, Equatable {}

    @Test func propagatesOperationError() async {
        do {
            _ = try await withTimeout(seconds: 10) { () throws -> Int in
                throw StubOpError()
            }
            Issue.record("expected operation error")
        } catch is StubOpError {
            // success — NOT TimeoutError
        } catch {
            Issue.record("expected StubOpError, got \(error)")
        }
    }

    @Test func cancellationFromCallerPropagates() async {
        let task = Task { () async throws -> String in
            try await withTimeout(seconds: 5) {
                try await Task.sleep(for: .seconds(5))
                return "late"
            }
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation or timeout")
        } catch is CancellationError {
            // success
        } catch is TimeoutError {
            // also acceptable — depending on which task observes the cancel first
        } catch {
            Issue.record("expected CancellationError or TimeoutError, got \(error)")
        }
    }

    @Test func supportsVoidReturn() async throws {
        try await withTimeout(seconds: 10) {
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
