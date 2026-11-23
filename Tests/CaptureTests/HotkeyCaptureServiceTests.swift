import BuddyCore
import XCTest
@testable import BuddyCapture

private final class FakeRegistrar: HotkeyRegistering, @unchecked Sendable {
    var handler: (@Sendable (HotkeyEdge) -> Void)?
    var registeredKey: UInt32?
    var registerCount = 0
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @Sendable (HotkeyEdge) -> Void) throws {
        registerCount += 1; registeredKey = keyCode; self.handler = handler
    }
    func unregister() {}
}
private struct FakeShots: ScreenshotTaking {
    let url: URL
    func capture() async throws -> URL { url }
}
private final class FakeSpeech: SpeechCapturing, @unchecked Sendable {
    var onPartial: (@Sendable (String) -> Void)?
    var failStart: Error?
    func start(onPartial: @escaping @Sendable (String) -> Void) throws {
        if let failStart { throw failStart }
        self.onPartial = onPartial
    }
    func stop(timeout: TimeInterval) async -> String { "hello buddy" }
}

final class HotkeyCaptureServiceTests: XCTestCase {
    private func make(speech: FakeSpeech, maxDuration: TimeInterval = 120, reg: FakeRegistrar) -> HotkeyCaptureService {
        HotkeyCaptureService(keyCode: 49, modifiers: 0, maxDuration: maxDuration, finalWait: 0.1, registrar: reg,
                             screenshots: FakeShots(url: URL(fileURLWithPath: "/tmp/x.png")),
                             makeSpeech: { speech }, clock: { Date() })
    }

    private func next(_ it: inout AsyncStream<CaptureEvent>.Iterator) async -> CaptureEvent? { await it.next() }

    func testFullFlowWithRepeats() async {
        let reg = FakeRegistrar(), speech = FakeSpeech()
        let svc = make(speech: speech, reg: reg)
        var it = svc.events().makeAsyncIterator()
        XCTAssertEqual(reg.registeredKey, 49)

        reg.handler?(.pressed)
        reg.handler?(.pressed) // repeat
        guard case .began = await next(&it) else { return XCTFail("expected began") }
        speech.onPartial?("hel")
        guard case .partial(let p) = await next(&it) else { return XCTFail("expected partial") }
        XCTAssertEqual(p, "hel")
        reg.handler?(.released)
        guard case .finished(let r) = await next(&it) else { return XCTFail("expected finished") }
        XCTAssertEqual(r.transcript, "hello buddy")
        XCTAssertEqual(r.screenshotURL?.lastPathComponent, "x.png")
    }

    func testMaxDurationAutoFinishes() async {
        let reg = FakeRegistrar(), speech = FakeSpeech()
        let svc = make(speech: speech, maxDuration: 0.1, reg: reg)
        var it = svc.events().makeAsyncIterator()
        reg.handler?(.pressed)
        _ = await next(&it) // began
        guard case .finished = await next(&it) else { return XCTFail("expected auto finish") }
        reg.handler?(.released) // must not emit a second result
    }

    func testSpeechStartFailureEmitsFailed() async {
        let reg = FakeRegistrar(), speech = FakeSpeech()
        speech.failStart = CaptureError.onDeviceUnsupported("he-IL")
        let svc = make(speech: speech, reg: reg)
        var it = svc.events().makeAsyncIterator()
        reg.handler?(.pressed)
        _ = await next(&it) // began
        guard case .failed(let msg) = await next(&it) else { return XCTFail("expected failed") }
        XCTAssertTrue(msg.contains("on-device") || msg.contains("On-device"))
    }
}
