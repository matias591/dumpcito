import BuddyCore
import Foundation

enum Fmt {
    /// Compact age for list rows: now, 4m, 2h, 3d.
    static func age(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "now"
        case ..<3_600: return "\(Int(s / 60))m"
        case ..<86_400: return "\(Int(s / 3_600))h"
        default: return "\(Int(s / 86_400))d"
        }
    }

    /// Replaces the home directory with `~`. Callers truncate from the head.
    static func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    static func countdown(to meeting: MeetingEvent, now: Date = Date()) -> String {
        let s = meeting.start.timeIntervalSince(now)
        if s >= 60 {
            let minutes = Int((s / 60).rounded())
            if minutes >= 60 { return "in \(minutes / 60)h \(minutes % 60)m" }
            return "in \(minutes) min"
        }
        if s > -60 { return "now" }
        if now < meeting.end { return "started \(Int(-s / 60)) min ago" }
        return "ended"
    }

    static func timeRange(_ meeting: MeetingEvent) -> String {
        let a = meeting.start.formatted(date: .omitted, time: .shortened)
        let b = meeting.end.formatted(date: .omitted, time: .shortened)
        return "\(a)\u{2013}\(b)"
    }

    /// Keeps the newest words of a live transcript. SwiftUI's multi-line `.head` truncation cuts
    /// mid-text, so trim by character budget instead (the transcript font is monospaced, so a
    /// budget maps to a predictable number of lines).
    static func tail(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        var suffix = text.suffix(maxChars - 1)
        if let space = suffix.firstIndex(of: " ") {
            suffix = suffix[suffix.index(after: space)...]
        }
        return "\u{2026}" + suffix
    }

    /// Working directory to offer for "New session": the most recently active session's cwd, else home.
    static func defaultNewSessionCwd(live: [AgentSession], recent: [AgentSession]) -> String {
        live.first?.cwd ?? recent.first?.cwd ?? NSHomeDirectory()
    }
}
