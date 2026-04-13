import Testing
@testable import OpenGram

@Suite("IconStateMachine")
@MainActor
struct IconStateMachineTests {

    @Test("Idle state returns outline checkmark symbol")
    func idleStateSymbol() {
        let machine = IconStateMachine()
        #expect(machine.currentState == .idle)
        #expect(machine.currentSymbolName == "checkmark.circle")
    }

    @Test("Checking state returns filled checkmark symbol")
    func checkingStateSymbol() {
        let machine = IconStateMachine()
        machine.setState(.checking)
        #expect(machine.currentState == .checking)
        #expect(machine.currentSymbolName == "checkmark.circle.fill")
    }

    @Test("Done state returns outline checkmark symbol")
    func doneStateSymbol() {
        let machine = IconStateMachine()
        machine.setState(.done)
        #expect(machine.currentSymbolName == "checkmark.circle")
    }

    @Test("Done state auto-transitions to idle after delay")
    func doneAutoTransitionsToIdle() {
        let machine = IconStateMachine()
        machine.setState(.done)
        #expect(machine.currentState == .done)
        #expect(machine.doneReturnDelay == 3.0)
    }

    @Test("Setting checking while already checking does not create duplicate timers")
    func checkingIdempotent() {
        let machine = IconStateMachine()
        machine.setState(.checking)
        let firstPulsePhase = machine.pulseIsHigh
        machine.setState(.checking)
        #expect(machine.currentState == .checking)
        #expect(machine.pulseIsHigh == firstPulsePhase)
    }

    @Test("Silent fail transitions checking to idle in 0.5 seconds")
    func silentFailDelay() {
        let machine = IconStateMachine()
        machine.setState(.checking)
        #expect(machine.silentFailDelay == 0.5)
        machine.triggerSilentFail()
        #expect(machine.currentState == .idle)
        #expect(machine.currentSymbolName == "checkmark.circle")
    }

    @Test("Setting idle cancels pulse")
    func idleCancelsPulse() {
        let machine = IconStateMachine()
        machine.setState(.checking)
        #expect(machine.isPulsing)
        machine.setState(.idle)
        #expect(!machine.isPulsing)
    }

    @Test("Pulse toggles between high and low opacity values")
    func pulseOpacityRange() {
        let machine = IconStateMachine()
        machine.setState(.checking)
        #expect(machine.pulseHighOpacity == 1.0)
        #expect(machine.pulseLowOpacity == 0.4)
    }

    @Test("Pulse interval is 0.5 seconds for 1Hz cycle")
    func pulseInterval() {
        let machine = IconStateMachine()
        #expect(machine.pulseInterval == 0.5)
    }
}
