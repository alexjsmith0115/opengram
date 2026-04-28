import Testing
import AppKit
@preconcurrency import ApplicationServices

@testable import OpenGramLib

// Reference-type box so escaping closures can share mutable state with their caller.
private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Stubs

private final class StubTextEngine: RewriteTextEngineProtocol, @unchecked Sendable {
    var nextResult: TextContext?
    var liveTextByRange: [String: String] = [:]  // key: "\(location):\(length)"
    var liveSelectedText: String?

    func extractText() -> TextContext? { nextResult }

    func readLiveText(at range: CFRange, of element: AXUIElement) -> String? {
        let key = "\(range.location):\(range.length)"
        return liveTextByRange[key]
    }

    func readLiveSelectedText(of element: AXUIElement) -> String? { liveSelectedText }
}

private final class StubTextReplacer: RewriteTextReplacerProtocol, @unchecked Sendable {
    var replaceResult = true
    var replaceCalls: [(strategy: WriteBackStrategy, replacement: String)] = []

    @discardableResult
    func replace(strategy: WriteBackStrategy,
                 replacement: String,
                 element: AXUIElement) -> Bool {
        replaceCalls.append((strategy: strategy, replacement: replacement))
        return replaceResult
    }
}

private struct StubConfig: RewriteConfigProvider {
    var llmConfig: LLMConfig { .default }
    func currentAPIKey() -> String? { "stub-key" }
}

private final class FakeController: RewriteWindowControlling, @unchecked Sendable {
    var nextShowResult: Bool = true
    var replacementCleanupCalled = false
    var failedShowCleanupCalled = false
    var hideCalled = false

    func show(near bounds: CGRect?) -> Bool { nextShowResult }
    func hide() { hideCalled = true }
    func teardownForSessionReplacement() { replacementCleanupCalled = true }
    func teardownForFailedShow() { failedShowCleanupCalled = true }
}

// MARK: - Context helpers

@MainActor
private func makeContext(
    text: String = "hello",
    selectionRange: CFRange? = CFRange(location: 0, length: 5),
    caps: AXCapabilities = AXCapabilities(
        canSetSelectedTextRange: true,
        canSetSelectedText: true,
        canReadSelectedText: true,
        canSetValue: false,
        canReadValue: false
    )
) -> TextContext {
    TextContext(
        text: text,
        bundleID: "com.test.app",
        extractionMethod: .axDirectSelection,
        selectionRange: selectionRange,
        elementBounds: CGRect(x: 100, y: 100, width: 200, height: 20),
        capabilities: caps,
        axElement: AXUIElementCreateSystemWide()
    )
}

// MARK: - Builder helpers

/// Returns a coordinator that records all constructed FakeControllers in `box`.
@MainActor
private func makeCoordinator(
    engine: StubTextEngine,
    replacer: StubTextReplacer,
    controllerBox: Box<[FakeController]>,
    nextShow: Bool = true,
    vmBox: Box<[RewriteWindowViewModel]>? = nil
) -> RewriteCoordinator {
    RewriteCoordinator(
        textEngine: engine,
        textReplacer: replacer,
        llmService: LLMService(),
        configManager: StubConfig(),
        statusBar: StatusBarController(),
        openSettings: {},
        buildController: { vm, _, _, _ in
            vmBox?.value.append(vm)
            let ctrl = FakeController()
            ctrl.nextShowResult = nextShow
            controllerBox.value.append(ctrl)
            return ctrl
        }
    )
}

// MARK: - Suite

@MainActor
@Suite("RewriteCoordinator")
struct RewriteCoordinatorTests {

    @Test("Empty selection → no panel created")
    func emptySelectionHint() {
        let engine = StubTextEngine()   // nextResult stays nil
        let replacer = StubTextReplacer()
        let box = Box<[FakeController]>([])
        let coordinator = makeCoordinator(engine: engine, replacer: replacer, controllerBox: box)
        coordinator.handleRewriteHotkey()
        #expect(box.value.isEmpty)
        #expect(coordinator.currentSnapshotIsNil)
    }

    @Test("extractText returns empty text → no panel created")
    func emptyTextHint() {
        let engine = StubTextEngine()
        engine.nextResult = makeContext(text: "")
        let replacer = StubTextReplacer()
        let box = Box<[FakeController]>([])
        let coordinator = makeCoordinator(engine: engine, replacer: replacer, controllerBox: box)
        coordinator.handleRewriteHotkey()
        #expect(box.value.isEmpty)
        #expect(coordinator.currentSnapshotIsNil)
    }

    @Test("extractText returns no viable strategy → no panel created")
    func noStrategyHint() {
        let engine = StubTextEngine()
        let caps = AXCapabilities(
            canSetSelectedTextRange: false,
            canSetSelectedText: false,
            canReadSelectedText: false,
            canSetValue: false,
            canReadValue: false
        )
        engine.nextResult = makeContext(text: "hello", selectionRange: nil, caps: caps)
        let replacer = StubTextReplacer()
        let box = Box<[FakeController]>([])
        let coordinator = makeCoordinator(engine: engine, replacer: replacer, controllerBox: box)
        coordinator.handleRewriteHotkey()
        #expect(box.value.isEmpty)
        #expect(coordinator.currentSnapshotIsNil)
    }

    @Test("Happy path: controller created and stored")
    func happyPathControllerCreated() {
        let engine = StubTextEngine()
        engine.nextResult = makeContext()
        let replacer = StubTextReplacer()
        let box = Box<[FakeController]>([])
        let coordinator = makeCoordinator(engine: engine, replacer: replacer, controllerBox: box)
        coordinator.handleRewriteHotkey()
        #expect(box.value.count == 1)
        #expect(!coordinator.currentSnapshotIsNil)
    }

    @Test("Rapid re-fire: prior controller torn down before new one shows")
    func atomicSwap() {
        let engine = StubTextEngine()
        engine.nextResult = makeContext()
        let replacer = StubTextReplacer()
        let box = Box<[FakeController]>([])
        let coordinator = makeCoordinator(engine: engine, replacer: replacer, controllerBox: box)

        coordinator.handleRewriteHotkey()
        #expect(box.value.count == 1)
        let a = box.value[0]

        coordinator.handleRewriteHotkey()
        #expect(box.value.count == 2)
        let b = box.value[1]

        #expect(a.replacementCleanupCalled == true, "A must be torn down before B shows")
        #expect(a.hideCalled == false, "replacementCleanup ≠ hide")
        #expect(!coordinator.currentSnapshotIsNil)
        _ = b
    }

    @Test("show() returning false triggers teardownForFailedShow, no current stored")
    func showFailureRollback() {
        let engine = StubTextEngine()
        engine.nextResult = makeContext()
        let replacer = StubTextReplacer()
        let box = Box<[FakeController]>([])
        let coordinator = makeCoordinator(engine: engine, replacer: replacer, controllerBox: box, nextShow: false)

        coordinator.handleRewriteHotkey()
        #expect(box.value.count == 1)
        #expect(box.value[0].failedShowCleanupCalled == true)
        #expect(coordinator.currentSnapshotIsNil)
    }

    @Test("Apply with matching live text writes back and dismisses")
    func applyHappyPath() throws {
        let engine = StubTextEngine()
        let range = CFRange(location: 0, length: 5)
        engine.nextResult = makeContext(text: "hello", selectionRange: range)
        engine.liveTextByRange["0:5"] = "hello"
        let replacer = StubTextReplacer()

        let box = Box<[FakeController]>([])
        let vmBox = Box<[RewriteWindowViewModel]>([])
        let coordinator = makeCoordinator(
            engine: engine, replacer: replacer, controllerBox: box, vmBox: vmBox)

        coordinator.handleRewriteHotkey()
        #expect(!coordinator.currentSnapshotIsNil)
        let vm = try #require(vmBox.value.first)

        // Set revised directly — apply() checks `revised`, not `canApply`/`status`.
        vm.revised = "Hi there"
        coordinator.applyForTest()

        #expect(replacer.replaceCalls.count == 1)
        #expect(replacer.replaceCalls[0].replacement == "Hi there")
        #expect(coordinator.currentSnapshotIsNil, "dismiss() must fire after successful write")
    }

    @Test("Apply with drifted live text → .targetChanged, no write")
    func applyTargetChanged() throws {
        let engine = StubTextEngine()
        let range = CFRange(location: 0, length: 5)
        engine.nextResult = makeContext(text: "hello", selectionRange: range)
        engine.liveTextByRange["0:5"] = "different"
        let replacer = StubTextReplacer()

        let box = Box<[FakeController]>([])
        let vmBox = Box<[RewriteWindowViewModel]>([])
        let coordinator = makeCoordinator(
            engine: engine, replacer: replacer, controllerBox: box, vmBox: vmBox)

        coordinator.handleRewriteHotkey()
        coordinator.applyForTest()

        #expect(replacer.replaceCalls.isEmpty)
        let vm = try #require(vmBox.value.first)
        if case .error(let err, _) = vm.status {
            #expect(err == .targetChanged)
        } else {
            Issue.record("Expected .error(.targetChanged), got \(vm.status)")
        }
    }

    @Test("Apply with nil live text → .targetUnavailable, no write")
    func applyTargetUnavailable() throws {
        let engine = StubTextEngine()
        let range = CFRange(location: 0, length: 5)
        engine.nextResult = makeContext(text: "hello", selectionRange: range)
        // liveTextByRange not set → returns nil
        let replacer = StubTextReplacer()

        let box = Box<[FakeController]>([])
        let vmBox = Box<[RewriteWindowViewModel]>([])
        let coordinator = makeCoordinator(
            engine: engine, replacer: replacer, controllerBox: box, vmBox: vmBox)

        coordinator.handleRewriteHotkey()
        coordinator.applyForTest()

        #expect(replacer.replaceCalls.isEmpty)
        let vm = try #require(vmBox.value.first)
        if case .error(let err, _) = vm.status {
            #expect(err == .targetUnavailable)
        } else {
            Issue.record("Expected .error(.targetUnavailable), got \(vm.status)")
        }
    }

    @Test("dismiss() hides current controller and clears snapshot")
    func dismissClearsSnapshot() {
        let engine = StubTextEngine()
        engine.nextResult = makeContext()
        let replacer = StubTextReplacer()
        let box = Box<[FakeController]>([])
        let coordinator = makeCoordinator(engine: engine, replacer: replacer, controllerBox: box)

        coordinator.handleRewriteHotkey()
        #expect(!coordinator.currentSnapshotIsNil)
        coordinator.dismiss()
        #expect(coordinator.currentSnapshotIsNil)
        #expect(box.value[0].hideCalled == true)
    }

    @Test("Apply with selectedTextOnly strategy reads selected text for freshness")
    func applySelectedTextOnlyPath() throws {
        let engine = StubTextEngine()
        let caps = AXCapabilities(
            canSetSelectedTextRange: false,
            canSetSelectedText: true,
            canReadSelectedText: true,
            canSetValue: false,
            canReadValue: false
        )
        engine.nextResult = makeContext(text: "hello", selectionRange: nil, caps: caps)
        engine.liveSelectedText = "hello"
        let replacer = StubTextReplacer()

        let box = Box<[FakeController]>([])
        let vmBox = Box<[RewriteWindowViewModel]>([])
        let coordinator = makeCoordinator(
            engine: engine, replacer: replacer, controllerBox: box, vmBox: vmBox)

        coordinator.handleRewriteHotkey()
        let vm = try #require(vmBox.value.first)
        vm.revised = "Hi"
        coordinator.applyForTest()

        #expect(replacer.replaceCalls.count == 1)
        #expect(replacer.replaceCalls[0].strategy == .selectedTextOnly)
    }

    @Test("replacer returning false → .writeFailed, snapshot not cleared")
    func writeFailureKeepsSnapshot() throws {
        let engine = StubTextEngine()
        let range = CFRange(location: 0, length: 5)
        engine.nextResult = makeContext(text: "hello", selectionRange: range)
        engine.liveTextByRange["0:5"] = "hello"
        let replacer = StubTextReplacer()
        replacer.replaceResult = false

        let box = Box<[FakeController]>([])
        let vmBox = Box<[RewriteWindowViewModel]>([])
        let coordinator = makeCoordinator(
            engine: engine, replacer: replacer, controllerBox: box, vmBox: vmBox)

        coordinator.handleRewriteHotkey()
        let vm = try #require(vmBox.value.first)
        vm.revised = "Hi"
        coordinator.applyForTest()

        #expect(!coordinator.currentSnapshotIsNil, "Session must stay open so user can copy")
        if case .error(let err, _) = vm.status {
            if case .writeFailed = err { } else {
                Issue.record("Expected .writeFailed, got \(err)")
            }
        } else {
            Issue.record("Expected .error(.writeFailed), got \(vm.status)")
        }
    }
}
