import Foundation

/// Pure helpers: file naming, pruning, downscale math. No system frameworks beyond Foundation.
public enum CaptureCleanup {
    /// Deletes screenshots older than the retention window. Called at launch so shots do not linger
    /// when the user stops using hold-to-talk.
    public static func pruneOld() { CaptureSupport.prune(dir: CaptureSupport.defaultBaseDir(), now: Date()) }
}

enum CaptureSupport {
    static let maxLongestSide = 1800
    static let retention: TimeInterval = 24 * 60 * 60

    /// Default ~/Library/Caches/Buddy/captures
    static func defaultBaseDir() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("Dumpcito/captures", isDirectory: true)
    }

    /// `yyyyMMdd-HHmmss` (POSIX digits, given time zone).
    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// Unique PNG URL inside `dir`: `<ts>.png`, or `<ts>-2.png`, `-3`... if taken within the same second.
    static func captureURL(in dir: URL, date: Date, timeZone: TimeZone = .current,
                           exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = timestamp(date, timeZone: timeZone)
        var url = dir.appendingPathComponent("\(base).png")
        var n = 2
        while exists(url) {
            url = dir.appendingPathComponent("\(base)-\(n).png")
            n += 1
        }
        return url
    }

    /// Target pixel size so the longest side <= maxSide. Never upscales; aspect preserved; min 1px.
    static func scaledSize(width: Int, height: Int, maxSide: Int = maxLongestSide) -> (width: Int, height: Int) {
        guard width > 0, height > 0, maxSide > 0 else { return (max(width, 1), max(height, 1)) }
        let longest = max(width, height)
        guard longest > maxSide else { return (width, height) }
        let scale = Double(maxSide) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// Deletes `.png` files in `dir` whose modification date is older than `olderThan` before `now`.
    /// Returns the number of files removed.
    @discardableResult
    static func prune(dir: URL, now: Date, olderThan: TimeInterval = retention,
                      fileManager fm: FileManager = .default) -> Int {
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return 0 }
        var removed = 0
        for file in files where file.pathExtension.lowercased() == "png" {
            guard let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            if now.timeIntervalSince(mtime) > olderThan {
                if (try? fm.removeItem(at: file)) != nil { removed += 1 }
            }
        }
        return removed
    }
}

/// Errors with user-facing text (surfaced as CaptureEvent.failed).
enum CaptureError: Error, LocalizedError {
    case screenRecordingMissing
    case microphoneMissing
    case speechMissing
    case onDeviceUnsupported(String)
    case recognizerUnavailable(String)
    case hotkeyRegistration(Int32)
    case screenshot(String)
    case audio(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingMissing: return "Screen Recording permission missing: System Settings > Privacy & Security > Screen Recording"
        case .microphoneMissing: return "Microphone permission missing: System Settings > Privacy & Security > Microphone"
        case .speechMissing: return "Speech Recognition permission missing: System Settings > Privacy & Security > Speech Recognition"
        case .onDeviceUnsupported(let l): return "On-device speech recognition is not available for locale \(l); refusing to send audio to Apple servers. Download the language under System Settings > Keyboard > Dictation."
        case .recognizerUnavailable(let l): return "Speech recognizer unavailable for locale \(l)."
        case .hotkeyRegistration(let s): return "Could not register global hotkey (OSStatus \(s)); another app may own this shortcut."
        case .screenshot(let m): return "Screenshot failed: \(m)"
        case .audio(let m): return "Microphone capture failed: \(m)"
        }
    }
}
