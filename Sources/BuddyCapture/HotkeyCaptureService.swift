@preconcurrency import AVFoundation
import Carbon.HIToolbox
import CoreGraphics
import BuddyCore
import Foundation
import Speech

/// Push-to-talk capture: hold the hotkey to screenshot + dictate, release to emit the result.
public final class HotkeyCaptureService: CaptureProviding, @unchecked Sendable {
    /// Control+Option
    public static let defaultModifiers = UInt32(controlKey | optionKey)
    public static let defaultKeyCode = UInt32(kVK_Space)

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let registrar: HotkeyRegistering
    private let screenshots: ScreenshotTaking
    private let makeSpeech: @Sendable () -> SpeechCapturing
    private let finalWait: TimeInterval
    private let clock: @Sendable () -> Date

    private let lock = NSLock()
    private var machine: PushToTalkMachine
    private var continuations: [UUID: AsyncStream<CaptureEvent>.Continuation] = [:]
    private var speech: SpeechCapturing?
    private var screenshotTask: Task<URL?, Never>?
    private var maxTimer: Task<Void, Never>?
    private var registered = false
    private var permissionsRunning = false

    public convenience init(keyCode: UInt32 = HotkeyCaptureService.defaultKeyCode,
                            modifiers: UInt32 = HotkeyCaptureService.defaultModifiers,
                            locale: Locale = .current,
                            maxDuration: TimeInterval = 120,
                            capturesDirectory: URL? = nil) {
        let screenshots = ScreenshotService(baseDir: capturesDirectory ?? CaptureSupport.defaultBaseDir())
        self.init(keyCode: keyCode, modifiers: modifiers, maxDuration: maxDuration, finalWait: 1.5,
                  registrar: CarbonHotkeyRegistrar(), screenshots: screenshots,
                  makeSpeech: { AppleSpeechSession(locale: locale) }, clock: { Date() })
    }

    /// Injectable designated init (tests).
    init(keyCode: UInt32, modifiers: UInt32, maxDuration: TimeInterval, finalWait: TimeInterval,
         registrar: HotkeyRegistering, screenshots: ScreenshotTaking,
         makeSpeech: @escaping @Sendable () -> SpeechCapturing, clock: @escaping @Sendable () -> Date) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.finalWait = finalWait
        self.registrar = registrar
        self.screenshots = screenshots
        self.makeSpeech = makeSpeech
        self.clock = clock
        self.machine = PushToTalkMachine(maxDuration: maxDuration)
    }

    deinit { registrar.unregister(); maxTimer?.cancel() }

    // MARK: CaptureProviding

    /// Each call returns an independent stream. The first call registers the global hotkey.
    public func events() -> AsyncStream<CaptureEvent> {
        let id = UUID()
        let (stream, cont) = AsyncStream<CaptureEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        lock.lock(); continuations[id] = cont; lock.unlock()
        cont.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.continuations[id] = nil; self.lock.unlock()
        }
        registerHotkeyIfNeeded()
        return stream
    }

    public func requestPermissions() async {
        guard beginPermissions() else { return }
        defer { endPermissions() }

        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess() // shows the OS prompt once; grant needs an app restart
            if !CGPreflightScreenCaptureAccess() { emit(.failed(CaptureError.screenRecordingMissing.localizedDescription)) }
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            let ok = await AVCaptureDevice.requestAccess(for: .audio)
            if !ok { emit(.failed(CaptureError.microphoneMissing.localizedDescription)) }
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
            }
            if status != .authorized { emit(.failed(CaptureError.speechMissing.localizedDescription)) }
        }
    }

    // MARK: Hotkey plumbing

    private func registerHotkeyIfNeeded() {
        lock.lock()
        if registered { lock.unlock(); return }
        registered = true
        lock.unlock()
        do {
            try registrar.register(keyCode: keyCode, modifiers: modifiers) { [weak self] edge in self?.handle(edge) }
        } catch {
            lock.lock(); registered = false; lock.unlock()
            emit(.failed(error.localizedDescription))
        }
    }

    func handle(_ edge: HotkeyEdge) {
        switch edge {
        case .pressed: handleDown()
        case .released: handleUp()
        }
    }

    private func handleDown() {
        lock.lock()
        let action = machine.keyDown(at: clock())
        lock.unlock()
        guard action == .start else { return }
        beginCapture()
    }

    private func handleUp() {
        lock.lock()
        let action = machine.keyUp()
        lock.unlock()
        if case .stop = action { endCapture() }
    }

    private func beginCapture() {
        emit(.began)

        let speech = makeSpeech()
        do {
            try speech.start { [weak self] text in self?.emit(.partial(text)) }
        } catch {
            lock.lock(); machine.abort(); lock.unlock()
            emit(.failed(error.localizedDescription))
            return
        }

        let shots = screenshots
        let shotTask = Task<URL?, Never> { [weak self] in
            do { return try await shots.capture() }
            catch {
                self?.emit(.failed(error.localizedDescription))
                return nil
            }
        }
        let maxDuration = machine.maxDuration
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(maxDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.handleTimeout()
        }
        lock.lock()
        self.speech = speech
        self.screenshotTask = shotTask
        self.maxTimer = timer
        lock.unlock()
    }

    private func handleTimeout() {
        lock.lock()
        let action = machine.tick(at: clock())
        lock.unlock()
        if case .stop = action { endCapture() }
    }

    private func endCapture() {
        lock.lock()
        let speech = self.speech, shotTask = self.screenshotTask, timer = self.maxTimer
        self.speech = nil; self.screenshotTask = nil; self.maxTimer = nil
        lock.unlock()
        timer?.cancel()

        let wait = finalWait
        Task { [weak self] in
            let transcript = await speech?.stop(timeout: wait) ?? ""
            let url = await shotTask?.value
            guard let self else { return }
            self.emit(.finished(CaptureResult(screenshotURL: url, transcript: transcript)))
            self.markFinished()
        }
    }

    private func markFinished() { lock.lock(); machine.finished(); lock.unlock() }
    private func beginPermissions() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if permissionsRunning { return false }
        permissionsRunning = true
        return true
    }
    private func endPermissions() { lock.lock(); permissionsRunning = false; lock.unlock() }

    private func emit(_ event: CaptureEvent) {
        lock.lock(); let conts = Array(continuations.values); lock.unlock()
        for c in conts { c.yield(event) }
    }
}
