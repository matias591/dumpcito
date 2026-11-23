import BuddyCore
import Foundation

/// Stored progress: counts per day and per track, plus short-lived dedupe keys. No titles, names or content.
public struct ProgressState: Codable, Equatable, Sendable {
    public var schema = 1
    /// "2026-11-05" -> track raw value -> count
    public var days: [String: [String: Int]] = [:]
    /// Dedupe key -> epoch seconds. Dropped after 48 hours.
    public var seen: [String: Double] = [:]
    public init() {}
}

/// XP, levels and pace, all derived from stored daily counts, so a formula change can never corrupt the data.
///
/// - Daily XP per track: 5 for any activity + 10 x min(count / baseline, 1). Beating your own pace earns nothing extra.
/// - Baseline: median count on your active days in the 28 days before that day (starter value if under 3 such days).
/// - Daily cap: 20 XP across tracks.
/// - Streak: each consecutive earlier week with activity on 3+ days adds 5% XP, up to 25%.
public enum ProgressEngine {
    public static let levelXP = [0, 50, 150, 300, 450, 650, 900, 1200, 1500, 1850]
    static let starterBaseline: [ProgressTrack: Double] = [.claude: 3, .meetings: 2]
    static let dailyCap = 20.0
    static let keepDays = 90

    public static func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    static func dayKey(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(of key: String, _ cal: Calendar) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    // MARK: Recording

    /// Counts one event unless `key` was already counted in the last 48 hours. Returns whether it counted.
    @discardableResult
    public static func record(_ track: ProgressTrack, key: String, at now: Date = Date(),
                              state: inout ProgressState, calendar cal: Calendar = calendar()) -> Bool {
        let cutoff = now.timeIntervalSince1970 - 48 * 3600
        state.seen = state.seen.filter { $0.value >= cutoff }
        let fullKey = "\(track.rawValue):\(key)"
        guard state.seen[fullKey] == nil else { return false }
        state.seen[fullKey] = now.timeIntervalSince1970
        let day = dayKey(now, cal)
        state.days[day, default: [:]][track.rawValue, default: 0] += 1
        if let limit = cal.date(byAdding: .day, value: -keepDays, to: now) {
            let oldest = dayKey(limit, cal)
            state.days = state.days.filter { $0.key >= oldest }
        }
        return true
    }

    // MARK: Derivation

    public static func level(forXP xp: Double) -> Int {
        var level = 1
        for (i, need) in levelXP.enumerated() where xp >= Double(need) { level = i + 1 }
        return level
    }

    static func stage(forLevel level: Int) -> Int {
        switch level {
        case ...2: 1
        case 3...4: 2
        case 5...6: 3
        case 7...9: 4
        default: 5
        }
    }

    private static func median(_ values: [Int]) -> Double {
        let v = values.sorted()
        guard !v.isEmpty else { return 0 }
        return v.count % 2 == 1 ? Double(v[v.count / 2]) : Double(v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }

    private static func weekKey(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// Total XP per track, with the streak bonus and the daily cap applied.
    static func trackXP(_ state: ProgressState, _ cal: Calendar) -> [ProgressTrack: Double] {
        let keys = state.days.keys.sorted()
        func count(_ key: String, _ t: ProgressTrack) -> Int { state.days[key]?[t.rawValue] ?? 0 }

        // Active days per week, for the streak.
        var weekDays: [String: Int] = [:]
        for key in keys where (state.days[key] ?? [:]).values.contains(where: { $0 > 0 }) {
            if let d = date(of: key, cal) { weekDays[weekKey(d, cal), default: 0] += 1 }
        }

        var xp: [ProgressTrack: Double] = [:]
        for key in keys {
            guard let day = date(of: key, cal) else { continue }
            var earned: [ProgressTrack: Double] = [:]
            for t in ProgressTrack.allCases {
                let c = count(key, t)
                guard c > 0 else { continue }
                var history: [Int] = []
                for back in 1...28 {
                    guard let d = cal.date(byAdding: .day, value: -back, to: day) else { continue }
                    let n = count(dayKey(d, cal), t)
                    if n > 0 { history.append(n) }
                }
                let baseline = history.count >= 3 ? max(1, median(history)) : (starterBaseline[t] ?? 3)
                earned[t] = 5 + 10 * min(Double(c) / baseline, 1)
            }
            let sum = earned.values.reduce(0, +)
            let scale = sum > dailyCap ? dailyCap / sum : 1

            var streak = 0
            var probe = day
            for _ in 0..<5 {
                guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: probe),
                      (weekDays[weekKey(prev, cal)] ?? 0) >= 3 else { break }
                streak += 1
                probe = prev
            }
            let bonus = 1 + 0.05 * Double(streak)
            for (t, v) in earned { xp[t, default: 0] += v * scale * bonus }
        }
        return xp
    }

    public static func summary(_ state: ProgressState, now: Date = Date(), calendar cal: Calendar = calendar()) -> ProgressSummary {
        let perTrack = trackXP(state, cal)
        let total = perTrack.values.reduce(0, +)
        let level = Self.level(forXP: total)
        let start = levelXP[level - 1]
        let next: Int? = level < levelXP.count ? levelXP[level] : nil

        let tracks = ProgressTrack.allCases.map { t -> TrackSummary in
            let txp = perTrack[t] ?? 0
            let tl = Self.level(forXP: txp)
            let a = Double(levelXP[tl - 1])
            let fraction = tl < levelXP.count ? (txp - a) / (Double(levelXP[tl]) - a) : 1
            var week = 0
            for back in 0..<7 {
                if let d = cal.date(byAdding: .day, value: -back, to: now) { week += state.days[dayKey(d, cal)]?[t.rawValue] ?? 0 }
            }
            return TrackSummary(id: t.rawValue, name: t.displayName, level: tl, fraction: min(1, max(0, fraction)), weekCount: week)
        }
        return ProgressSummary(level: level, xp: Int(total.rounded(.down)), levelStartXP: start, nextLevelXP: next,
                               stage: stage(forLevel: level), pace: pace(state, now, cal), tracks: tracks)
    }

    /// Neutral wording by design. Compares the last 7 days with your own earlier weeks.
    static func pace(_ state: ProgressState, _ now: Date, _ cal: Calendar) -> String {
        func active(_ key: String) -> Bool { (state.days[key] ?? [:]).values.contains { $0 > 0 } }
        var recent = 0, earlier = 0
        for back in 0..<35 {
            guard let d = cal.date(byAdding: .day, value: -back, to: now), active(dayKey(d, cal)) else { continue }
            if back < 7 { recent += 1 } else { earlier += 1 }
        }
        let firstDay = state.days.keys.filter { active($0) }.sorted().first.flatMap { date(of: $0, cal) }
        let age = firstDay.map { cal.dateComponents([.day], from: $0, to: now).day ?? 0 } ?? 0
        if state.days.isEmpty || age < 7 { return "Getting started" }
        if recent == 0 { return "Resting" }
        let usual = max(1, Double(earlier) / 4)
        let ratio = Double(recent) / usual
        return ratio >= 1.2 ? "Above your usual" : (ratio >= 0.6 ? "On pace" : "Light week")
    }
}

/// Reads and writes the progress file. Owner-only, atomic, and a corrupt file is moved aside, never silently lost.
public struct ProgressStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dumpcito/progress.json")
    }

    public let url: URL
    public init(url: URL = ProgressStore.defaultURL) { self.url = url }

    public func load() -> ProgressState {
        guard let data = try? Data(contentsOf: url) else { return ProgressState() }
        if let state = try? JSONDecoder().decode(ProgressState.self, from: data) { return state }
        let aside = url.deletingLastPathComponent().appendingPathComponent("progress.corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return ProgressState()
    }

    public func save(_ state: ProgressState) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Progress is a nicety; never let a write failure disturb alerts.
        }
    }

    public func delete() { try? FileManager.default.removeItem(at: url) }
}
