import XCTest
@testable import BuddyCapture

final class PushToTalkMachineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testDownUp() {
        var m = PushToTalkMachine(maxDuration: 120)
        XCTAssertEqual(m.keyDown(at: t0), .start)
        XCTAssertEqual(m.keyUp(), .stop(.released))
        m.finished()
        XCTAssertEqual(m.phase, .idle)
    }

    func testKeyRepeatIgnored() {
        var m = PushToTalkMachine()
        XCTAssertEqual(m.keyDown(at: t0), .start)
        for i in 1...5 { XCTAssertEqual(m.keyDown(at: t0.addingTimeInterval(Double(i) * 0.03)), .none) }
        XCTAssertEqual(m.keyUp(), .stop(.released))
    }

    func testStrayUpIgnored() {
        var m = PushToTalkMachine()
        XCTAssertEqual(m.keyUp(), .none)
    }

    func testDoublePressWhileFinishingIgnoredThenAllowed() {
        var m = PushToTalkMachine()
        _ = m.keyDown(at: t0)
        _ = m.keyUp()
        XCTAssertEqual(m.keyDown(at: t0.addingTimeInterval(0.1)), .none) // still finishing
        XCTAssertEqual(m.keyUp(), .none)
        m.finished()
        XCTAssertEqual(m.keyDown(at: t0.addingTimeInterval(1)), .start)
    }

    func testMaxDurationAutoFinishAndNoRestartWhileHeld() {
        var m = PushToTalkMachine(maxDuration: 120)
        _ = m.keyDown(at: t0)
        XCTAssertEqual(m.tick(at: t0.addingTimeInterval(119)), .none)
        XCTAssertEqual(m.tick(at: t0.addingTimeInterval(120)), .stop(.maxDuration))
        XCTAssertEqual(m.tick(at: t0.addingTimeInterval(121)), .none) // only once
        m.finished()
        XCTAssertEqual(m.keyDown(at: t0.addingTimeInterval(122)), .none) // repeat while still held
        XCTAssertEqual(m.keyUp(), .none)
        XCTAssertEqual(m.keyDown(at: t0.addingTimeInterval(130)), .start)
    }

    func testAbortReturnsToIdle() {
        var m = PushToTalkMachine()
        _ = m.keyDown(at: t0)
        m.abort()
        XCTAssertEqual(m.keyUp(), .none)
        XCTAssertEqual(m.keyDown(at: t0.addingTimeInterval(1)), .start)
    }
}
