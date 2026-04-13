import Foundation

@MainActor
final class IconStateMachine {
    private(set) var currentState: AppState = .idle

    let doneReturnDelay: TimeInterval = 3.0
    let silentFailDelay: TimeInterval = 0.5
    let pulseInterval: TimeInterval = 0.5
    let pulseHighOpacity: CGFloat = 1.0
    let pulseLowOpacity: CGFloat = 0.4

    private(set) var isPulsing = false
    private(set) var pulseIsHigh = true

    private var pulseTimer: Timer?
    private var doneTimer: Timer?

    var currentSymbolName: String {
        currentState.sfSymbolName
    }

    var currentOpacity: CGFloat {
        guard isPulsing else { return 1.0 }
        return pulseIsHigh ? pulseHighOpacity : pulseLowOpacity
    }

    var onStateChange: ((AppState, String, CGFloat) -> Void)?

    func setState(_ state: AppState) {
        cancelDoneTimer()

        switch state {
        case .idle:
            cancelPulse()
            currentState = .idle
            notifyChange()

        case .checking:
            if currentState == .checking { return }
            currentState = .checking
            startPulse()
            notifyChange()

        case .done:
            cancelPulse()
            currentState = .done
            notifyChange()
            scheduleDoneReturn()
        }
    }

    func triggerSilentFail() {
        cancelPulse()
        cancelDoneTimer()
        currentState = .idle
        notifyChange()
    }

    private func startPulse() {
        cancelPulse()
        isPulsing = true
        pulseIsHigh = true

        pulseTimer = Timer.scheduledTimer(withTimeInterval: pulseInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pulseIsHigh.toggle()
                self.notifyChange()
            }
        }
    }

    private func cancelPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        isPulsing = false
        pulseIsHigh = true
    }

    private func scheduleDoneReturn() {
        doneTimer = Timer.scheduledTimer(withTimeInterval: doneReturnDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setState(.idle)
            }
        }
    }

    private func cancelDoneTimer() {
        doneTimer?.invalidate()
        doneTimer = nil
    }

    private func notifyChange() {
        onStateChange?(currentState, currentSymbolName, currentOpacity)
    }
}
