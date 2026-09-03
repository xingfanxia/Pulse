import XCTest
@testable import Pulse

final class ClauthSwitchMachineTests: XCTestCase {
    typealias M = ClauthSwitchMachine

    func testRequestArmsWhenTheCurrentAccountHasALiveSession() {
        XCTAssertEqual(M.reduce(.idle, .requestSwitch(target: "b", currentHasLiveSession: true)), .arming(target: "b"))
        XCTAssertEqual(M.reduce(.idle, .requestSwitch(target: "b", currentHasLiveSession: false)), .pending(target: "b"))
    }

    func testARequestNeverInterruptsAPendingSwitch() {
        XCTAssertEqual(M.reduce(.pending(target: "a"), .requestSwitch(target: "b", currentHasLiveSession: false)), .pending(target: "a"))
        XCTAssertEqual(M.reduce(.confirmed(target: "a", viaCLI: false), .requestSwitch(target: "b", currentHasLiveSession: false)), .pending(target: "b"))
        XCTAssertEqual(M.reduce(.failed(reason: "x"), .requestSwitch(target: "b", currentHasLiveSession: true)), .arming(target: "b"))
    }

    func testArmConfirmCancelAndTimeout() {
        XCTAssertEqual(M.reduce(.arming(target: "b"), .confirmArm), .pending(target: "b"))
        XCTAssertEqual(M.reduce(.idle, .confirmArm), .idle)
        XCTAssertEqual(M.reduce(.arming(target: "b"), .cancel), .idle)
        XCTAssertEqual(M.reduce(.arming(target: "b"), .armTimedOut), .idle)
        XCTAssertEqual(M.reduce(.pending(target: "b"), .armTimedOut), .pending(target: "b"))
    }

    func testDispatchOutcomes() {
        XCTAssertEqual(M.reduce(.pending(target: "b"), .dispatched(.accepted)), .pending(target: "b"))
        XCTAssertEqual(M.reduce(.pending(target: "b"), .dispatched(.confirmedByCLI)), .confirmed(target: "b", viaCLI: true))
        XCTAssertEqual(M.reduce(.pending(target: "b"), .dispatched(.refused(code: "busy", message: "busy"))), .failed(reason: "busy"))
        XCTAssertEqual(M.reduce(.pending(target: "b"), .dispatched(.unreachable)), .failed(reason: "clauth daemon not reachable — is it running?"))
        XCTAssertEqual(M.reduce(.idle, .dispatched(.accepted)), .idle)
    }

    func testObservedActiveConfirmsOnlyTheTarget() {
        XCTAssertEqual(M.reduce(.pending(target: "b"), .observedActive("b")), .confirmed(target: "b", viaCLI: false))
        XCTAssertEqual(M.reduce(.pending(target: "b"), .observedActive("a")), .pending(target: "b"))
        XCTAssertEqual(M.reduce(.pending(target: "b"), .observedActive(nil)), .pending(target: "b"))
        XCTAssertEqual(M.reduce(.arming(target: "b"), .observedActive("b")), .arming(target: "b"))
    }

    func testPendingTimeoutAndDismiss() {
        XCTAssertEqual(M.reduce(.pending(target: "b"), .pendingTimedOut), .failed(reason: "the switch didn’t take — the daemon may be busy"))
        XCTAssertEqual(M.reduce(.confirmed(target: "b", viaCLI: false), .dismiss), .idle)
        XCTAssertEqual(M.reduce(.failed(reason: "x"), .dismiss), .idle)
        XCTAssertEqual(M.reduce(.pending(target: "b"), .dismiss), .pending(target: "b"))
    }

    func testBusyAndInFlightTarget() {
        XCTAssertTrue(M.Phase.arming(target: "b").isBusy)
        XCTAssertTrue(M.Phase.pending(target: "b").isBusy)
        XCTAssertFalse(M.Phase.confirmed(target: "b", viaCLI: false).isBusy)
        XCTAssertEqual(M.Phase.pending(target: "b").inFlightTarget, "b")
        XCTAssertNil(M.Phase.failed(reason: "x").inFlightTarget)
    }

    func testPendingExtendsOnlyWhileTheDaemonHoldsTheTargetUnderTheCeiling() {
        XCTAssertTrue(M.shouldExtendPending(daemonPending: "b", target: "b", elapsed: 6))
        XCTAssertFalse(M.shouldExtendPending(daemonPending: "a", target: "b", elapsed: 6))
        XCTAssertFalse(M.shouldExtendPending(daemonPending: nil, target: "b", elapsed: 6))
        XCTAssertFalse(M.shouldExtendPending(daemonPending: "b", target: "b", elapsed: 30))
    }
}
