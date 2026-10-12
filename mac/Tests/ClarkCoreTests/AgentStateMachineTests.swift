import XCTest
@testable import ClarkCore

final class AgentStateMachineTests: XCTestCase {
    /// Agente que saiu do BOOT e está parado em IDLE no instante 5.
    private func idleMachine() -> AgentStateMachine {
        var machine = AgentStateMachine(now: 0)
        machine.tick(now: 5, watched: false)
        XCTAssertEqual(machine.state, .idle)
        return machine
    }

    /// Faz o agente trabalhar de `start` até `end` com saída a cada 0,5 s e tique a cada 0,1 s.
    private func work(_ machine: inout AgentStateMachine, from start: Double, to end: Double, watched: Bool = false) {
        var now = start
        while now <= end + 0.0001 {
            machine.output(now: now)
            for step in 1...5 { machine.tick(now: now + Double(step) * 0.1, watched: watched) }
            now += 0.5
        }
    }

    func testBootBecomesIdleAfterTwoSeconds() {
        var machine = AgentStateMachine(now: 0)
        XCTAssertEqual(machine.state, .boot)
        XCTAssertFalse(machine.tick(now: 1.9, watched: false))
        XCTAssertEqual(machine.state, .boot)
        XCTAssertFalse(machine.tick(now: 2.1, watched: false))
        XCTAssertEqual(machine.state, .idle)
    }

    func testOutputMakesItWorking() {
        var machine = idleMachine()
        machine.output(now: 6)
        machine.tick(now: 6.1, watched: false)
        XCTAssertEqual(machine.state, .working)
        XCTAssertEqual(machine.lastChange, 6)
    }

    func testOutputRightAfterAKeyIsEcho() {
        var machine = idleMachine()
        machine.userInput(now: 6)
        machine.output(now: 6.2)
        machine.tick(now: 6.25, watched: false)
        XCTAssertEqual(machine.state, .idle)
        machine.output(now: 6.4)
        machine.tick(now: 6.45, watched: false)
        XCTAssertEqual(machine.state, .working)
    }

    func testLongWorkAfterInputEndsInDoneAndNotifies() {
        var machine = idleMachine()
        machine.userInput(now: 10)
        work(&machine, from: 10.5, to: 13.5)
        XCTAssertEqual(machine.state, .working)
        XCTAssertFalse(machine.tick(now: 14.4, watched: false))
        XCTAssertTrue(machine.tick(now: 14.6, watched: false))
        XCTAssertEqual(machine.state, .done)
        XCTAssertFalse(machine.tick(now: 14.7, watched: false), "notifica uma vez só")
        XCTAssertEqual(machine.state, .done)
    }

    func testLongWorkWhileWatchedEndsInIdle() {
        var machine = idleMachine()
        machine.userInput(now: 10)
        work(&machine, from: 10.5, to: 13.5, watched: true)
        XCTAssertFalse(machine.tick(now: 14.6, watched: true))
        XCTAssertEqual(machine.state, .idle)
    }

    func testLongWorkWithoutInputEndsInIdle() {
        var machine = idleMachine()
        work(&machine, from: 10.5, to: 13.5)
        XCTAssertFalse(machine.tick(now: 14.6, watched: false))
        XCTAssertEqual(machine.state, .idle)
    }

    func testShortWorkEndsInIdle() {
        var machine = idleMachine()
        machine.userInput(now: 10)
        work(&machine, from: 10.5, to: 11.5)
        XCTAssertFalse(machine.tick(now: 12.6, watched: false))
        XCTAssertEqual(machine.state, .idle)
    }

    func testBellNotifiesUnlessWatched() {
        var machine = idleMachine()
        XCTAssertTrue(machine.bell(watched: false))
        XCTAssertEqual(machine.state, .done)

        var watched = idleMachine()
        watched.output(now: 6)
        watched.tick(now: 6.1, watched: true)
        XCTAssertEqual(watched.state, .working)
        XCTAssertFalse(watched.bell(watched: true))
        XCTAssertEqual(watched.state, .idle)
    }

    func testKeyAndFocusClearDone() {
        var byKey = idleMachine()
        byKey.bell(watched: false)
        byKey.userInput(now: 6)
        XCTAssertEqual(byKey.state, .idle)
        XCTAssertTrue(byKey.hasInput)

        var byFocus = idleMachine()
        byFocus.bell(watched: false)
        byFocus.focused(now: 6)
        XCTAssertEqual(byFocus.state, .idle)
    }

    func testFocusSilencesOutputForThreeTenths() {
        var machine = idleMachine()
        machine.focused(now: 6)
        machine.output(now: 6.2)
        machine.tick(now: 6.25, watched: true)
        XCTAssertEqual(machine.state, .idle)
        machine.output(now: 6.35)
        machine.tick(now: 6.4, watched: true)
        XCTAssertEqual(machine.state, .working)
    }

    func testResizeSilencesForHalfASecond() {
        var machine = idleMachine()
        machine.resized(now: 6)
        machine.output(now: 6.4)
        machine.tick(now: 6.45, watched: false)
        XCTAssertEqual(machine.state, .idle)
        machine.output(now: 6.6)
        machine.tick(now: 6.65, watched: false)
        XCTAssertEqual(machine.state, .working)
    }

    func testLayoutChangeSilencesForEightTenths() {
        var machine = idleMachine()
        machine.layoutChanged(now: 6)
        machine.output(now: 6.7)
        machine.tick(now: 6.75, watched: false)
        XCTAssertEqual(machine.state, .idle)
        machine.output(now: 6.9)
        machine.tick(now: 6.95, watched: false)
        XCTAssertEqual(machine.state, .working)
    }

    func testShorterSilenceDoesNotCutALongerOne() {
        var machine = idleMachine()
        machine.layoutChanged(now: 6)
        machine.focused(now: 6.1)
        machine.output(now: 6.7)
        machine.tick(now: 6.75, watched: false)
        XCTAssertEqual(machine.state, .idle)
    }

    func testExitedIsFinalUntilRespawn() {
        var machine = idleMachine()
        machine.exited()
        XCTAssertEqual(machine.state, .exited)
        machine.output(now: 6)
        XCTAssertFalse(machine.tick(now: 6.1, watched: false))
        XCTAssertEqual(machine.state, .exited)
        XCTAssertFalse(machine.bell(watched: false))
        XCTAssertEqual(machine.state, .exited)

        machine.userInput(now: 7)
        machine.spawned(now: 8)
        XCTAssertEqual(machine.state, .boot)
        XCTAssertFalse(machine.hasInput)
        machine.tick(now: 9, watched: false)
        XCTAssertEqual(machine.state, .boot, "o BOOT conta a partir do respawn")
        machine.tick(now: 10.1, watched: false)
        XCTAssertEqual(machine.state, .idle)
    }

    func testExitWhileWorkingDoesNotNotify() {
        var machine = idleMachine()
        machine.userInput(now: 10)
        work(&machine, from: 10.5, to: 13.5)
        machine.exited()
        XCTAssertFalse(machine.tick(now: 14.6, watched: false))
        XCTAssertEqual(machine.state, .exited)
    }
}
