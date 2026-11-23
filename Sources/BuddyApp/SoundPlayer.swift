import AVFoundation
import Foundation

enum BuddySound: String, CaseIterable {
    case needsYou = "needs-you"
    case meeting
    case finished
}

/// Short event sounds. Each one is synthesized once (original blips, nothing sampled), unless the user drops a
/// file named after the sound (needs-you, meeting, finished; wav/aiff/mp3/m4a) into ~/.dumpcito/sounds.
@MainActor
final class SoundPlayer {
    static let enabledKey = "buddy.sounds"
    static let userDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dumpcito/sounds")

    private var player: AVAudioPlayer?

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    func play(_ sound: BuddySound) {
        guard isEnabled else { return }
        let data: Data
        if let url = Self.userFile(for: sound), let d = try? Data(contentsOf: url) { data = d } else { data = Self.synthesized(sound) }
        player = try? AVAudioPlayer(data: data)
        player?.volume = 0.6
        player?.play()
    }

    private static func userFile(for sound: BuddySound) -> URL? {
        for ext in ["wav", "aiff", "mp3", "m4a"] {
            let url = userDir.appendingPathComponent("\(sound.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    // MARK: Synthesis

    /// (frequency Hz, start s, length s)
    private static func notes(_ sound: BuddySound) -> [(Double, Double, Double)] {
        switch sound {
        case .needsYou: [(784, 0, 0.16), (587, 0.17, 0.26)]            // descending "uh-oh"
        case .meeting: [(659, 0, 0.12), (784, 0.14, 0.12), (988, 0.28, 0.2)]
        case .finished: [(784, 0, 0.1), (1047, 0.1, 0.2)]
        }
    }

    static func synthesized(_ sound: BuddySound) -> Data {
        let rate = 44100.0
        let notes = notes(sound)
        let total = (notes.map { $0.1 + $0.2 }.max() ?? 0) + 0.05
        var samples = [Int16](repeating: 0, count: Int(total * rate))
        for (freq, start, length) in notes {
            let first = Int(start * rate)
            for i in 0..<Int(length * rate) where first + i < samples.count {
                let t = Double(i) / rate
                let attack = min(1, t / 0.006)
                let decay = exp(-t / (length * 0.45))
                let wave = sin(2 * .pi * freq * t) + 0.3 * sin(4 * .pi * freq * t)
                let v = Int(wave * attack * decay * 9000)
                samples[first + i] = Int16(clamping: Int(samples[first + i]) + v)
            }
        }
        return wav(samples, rate: Int(rate))
    }

    private static func wav(_ samples: [Int16], rate: Int) -> Data {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + samples.count * 2)
        d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(samples.count * 2)
        for s in samples { u16(Int(UInt16(bitPattern: s))) }
        return d
    }
}
