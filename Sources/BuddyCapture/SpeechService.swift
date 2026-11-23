@preconcurrency import AVFoundation
import Foundation
import Speech

protocol SpeechCapturing: AnyObject, Sendable {
    /// Starts mic + recognition. Throws CaptureError (permissions, no on-device support).
    func start(onPartial: @escaping @Sendable (String) -> Void) throws
    /// Ends audio, waits up to `timeout` for the final result, returns best transcript.
    func stop(timeout: TimeInterval) async -> String
}

/// Resume-once helper for the final-result wait.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<Void, Never>?
    private var fired = false
    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired { lock.unlock(); c.resume() } else { cont = c; lock.unlock() }
        }
    }
    func fire() {
        lock.lock()
        fired = true
        let c = cont; cont = nil
        lock.unlock()
        c?.resume()
    }
}

/// AVAudioEngine tap -> SFSpeechRecognizer, strictly on-device.
/// Verified by compilation only (needs Microphone + Speech TCC and an app bundle).
final class AppleSpeechSession: SpeechCapturing, @unchecked Sendable {
    private let locale: Locale
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private let gate = OnceGate()

    init(locale: Locale) { self.locale = locale }

    /// Requested locale if supported, else en-US.
    static func resolveLocale(_ requested: Locale) -> Locale {
        if SFSpeechRecognizer(locale: requested) != nil { return requested }
        return Locale(identifier: "en-US")
    }

    func start(onPartial: @escaping @Sendable (String) -> Void) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw CaptureError.microphoneMissing }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw CaptureError.speechMissing }

        let loc = Self.resolveLocale(locale)
        guard let recognizer = SFSpeechRecognizer(locale: loc), recognizer.isAvailable else {
            throw CaptureError.recognizerUnavailable(loc.identifier)
        }
        guard recognizer.supportsOnDeviceRecognition else { throw CaptureError.onDeviceUnsupported(loc.identifier) }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw CaptureError.audio("no input device") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw CaptureError.audio(error.localizedDescription)
        }

        let gate = self.gate
        let task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                self?.setLatest(text)
                onPartial(text)
                if result.isFinal { gate.fire() }
            }
            if error != nil { gate.fire() }
        }
        lock.lock(); self.engine = engine; self.request = req; self.task = task; lock.unlock()
    }

    private func setLatest(_ t: String) { lock.lock(); latest = t; lock.unlock() }

    func stop(timeout: TimeInterval) async -> String {
        lock.lock()
        let engine = self.engine, req = self.request, task = self.task
        self.engine = nil; self.request = nil; self.task = nil
        lock.unlock()

        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        req?.endAudio()

        if task != nil {
            let gate = self.gate
            let timer = Task { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); gate.fire() }
            await gate.wait()
            timer.cancel()
            task?.cancel()
        }
        lock.lock(); let text = latest; lock.unlock()
        return text
    }
}
