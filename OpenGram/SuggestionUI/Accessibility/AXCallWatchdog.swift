import Foundation

/// Thread-safe watchdog that tracks active AX calls and blocklists apps that hang.
///
/// When an AX call exceeds `hangThreshold` seconds, the calling app's bundle ID is
/// added to a blocklist with a `blocklistDuration` expiration. All callers check
/// `shouldSkip(for:)` before making AX calls to avoid blocking on misbehaving apps.
final class AXCallWatchdog: @unchecked Sendable {

    static let shared = AXCallWatchdog()

    private let lock = NSLock()
    private var activeCall: ActiveCall?
    private var blocklist: [String: Date] = [:]
    private let hangThreshold: TimeInterval
    private let blocklistDuration: TimeInterval
    private var timer: DispatchSourceTimer?

    struct ActiveCall {
        let bundleID: String
        let startTime: Date
        let attribute: String
    }

    init() {
        self.hangThreshold = 0.8
        self.blocklistDuration = 30.0
        startTimer()
    }

    // Internal init for tests to use shorter thresholds so tests run fast.
    init(hangThreshold: TimeInterval, blocklistDuration: TimeInterval) {
        self.hangThreshold = hangThreshold
        self.blocklistDuration = blocklistDuration
        startTimer()
    }

    // MARK: - Public API

    /// Returns true if the given bundle ID is on the blocklist. Busy-guard removed —
    /// call serialization is the queue's responsibility.
    func shouldSkip(for bundleID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let expiration = blocklist[bundleID] {
            if Date() < expiration { return true }
            blocklist.removeValue(forKey: bundleID)
        }
        return false  // No busy guard — queue handles serialization.
    }

    /// Marks the start of an AX call for the given bundle ID.
    func beginCall(bundleID: String, attribute: String) {
        lock.lock()
        defer { lock.unlock() }
        activeCall = ActiveCall(bundleID: bundleID, startTime: Date(), attribute: attribute)
    }

    /// Marks the end of the current AX call, clearing active state.
    func endCall() {
        lock.lock()
        defer { lock.unlock() }
        activeCall = nil
    }

    // MARK: - Private

    private func startTimer() {
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + 0.1, repeating: 0.1)
        source.setEventHandler { [weak self] in
            self?.checkForHang()
        }
        source.resume()
        timer = source
    }

    private func checkForHang() {
        lock.lock()
        defer { lock.unlock() }
        guard let call = activeCall else { return }
        let elapsed = Date().timeIntervalSince(call.startTime)
        guard elapsed > hangThreshold else { return }
        blocklist[call.bundleID] = Date().addingTimeInterval(blocklistDuration)
        activeCall = nil
    }
}
