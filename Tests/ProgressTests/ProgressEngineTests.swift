import XCTest
import BuddyCore
@testable import BuddyProgress

final class ProgressEngineTests: XCTestCase {
    private let cal = ProgressEngine.calendar()
    private func date(_ s: String, hour: Int = 12) -> Date {
        let p = s.split(separator: "-").compactMap { Int($0) }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
    }
    private func state(_ days: [String: [ProgressTrack: Int]]) -> ProgressState {
        var s = ProgressState()
        for (k, v) in days { s.days[k] = Dictionary(uniqueKeysWithValues: v.map { ($0.key.rawValue, $0.value) }) }
        return s
    }

    func testLevelTable() {
        XCTAssertEqual(ProgressEngine.level(forXP: 0), 1)
        XCTAssertEqual(ProgressEngine.level(forXP: 49), 1)
        XCTAssertEqual(ProgressEngine.level(forXP: 50), 2)
        XCTAssertEqual(ProgressEngine.level(forXP: 1849), 9)
        XCTAssertEqual(ProgressEngine.level(forXP: 1850), 10)
        XCTAssertEqual(ProgressEngine.level(forXP: 99999), 10)
    }

    func testRecordCountsOncePerKeyAndDropsOldKeys() {
        var s = ProgressState()
        let t0 = date("2026-11-05")
        XCTAssertTrue(ProgressEngine.record(.claude, key: "a", at: t0, state: &s))
        XCTAssertFalse(ProgressEngine.record(.claude, key: "a", at: t0.addingTimeInterval(60), state: &s), "same key within 48h")
        XCTAssertTrue(ProgressEngine.record(.meetings, key: "a", at: t0, state: &s), "keys are per track")
        XCTAssertTrue(ProgressEngine.record(.claude, key: "a", at: t0.addingTimeInterval(49 * 3600), state: &s), "key expired")
        XCTAssertEqual(s.days["2026-11-05"]?["claude"], 1)
    }

    func testFirstDayXPUsesStarterBaselineAndNeverExceedsPace() {
        // 6 sessions on a starter baseline of 3 earns the same as 3: beating your pace pays nothing extra.
        let a = ProgressEngine.summary(state(["2026-11-05": [.claude: 3]]), now: date("2026-11-05"), calendar: cal)
        let b = ProgressEngine.summary(state(["2026-11-05": [.claude: 6]]), now: date("2026-11-05"), calendar: cal)
        XCTAssertEqual(a.xp, 15)
        XCTAssertEqual(b.xp, 15)
        let light = ProgressEngine.summary(state(["2026-11-05": [.claude: 1]]), now: date("2026-11-05"), calendar: cal)
        XCTAssertEqual(light.xp, 8, "5 + 10 x 1/3, rounded down")
    }

    func testDailyCapAcrossTracks() {
        let s = ProgressEngine.summary(state(["2026-11-05": [.claude: 5, .meetings: 5]]), now: date("2026-11-05"), calendar: cal)
        XCTAssertEqual(s.xp, 20, "two full tracks would be 30; capped at 20")
    }

    func testBaselineIsPersonal() {
        // Ten earlier days at 10 sessions: baseline 10, so 5 sessions earns 5 + 10 x 0.5 = 10.
        var days: [String: [ProgressTrack: Int]] = [:]
        for d in 1...10 { days[String(format: "2026-10-%02d", d)] = [.claude: 10] }
        let base = ProgressEngine.summary(state(days), now: date("2026-10-10"), calendar: cal).xp
        days["2026-11-05"] = [.claude: 5]
        let withDay = ProgressEngine.summary(state(days), now: date("2026-11-05"), calendar: cal).xp
        XCTAssertEqual(withDay - base, 10)
    }

    func testStreakBonusFromEarlierWeeks() {
        // Two earlier weeks with 3 active days each, then a day in week three.
        var days: [String: [ProgressTrack: Int]] = [:]
        for d in ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-26", "2026-10-27", "2026-10-28"] { days[d] = [.claude: 3] }
        let plain = ProgressEngine.summary(state(days), now: date("2026-10-28"), calendar: cal).xp
        days["2026-11-03"] = [.claude: 3]
        let total = ProgressEngine.summary(state(days), now: date("2026-11-03"), calendar: cal).xp
        XCTAssertEqual(total - plain, 16, "15 XP x 1.10 streak bonus, rounded down")
    }

    func testLevelsNeverDropWhenActivityStops() {
        var days: [String: [ProgressTrack: Int]] = [:]
        for d in 1...28 { days[String(format: "2026-09-%02d", min(d, 30))] = [.claude: 3, .meetings: 2] }
        let early = ProgressEngine.summary(state(days), now: date("2026-09-28"), calendar: cal)
        let later = ProgressEngine.summary(state(days), now: date("2026-11-30"), calendar: cal)
        XCTAssertEqual(later.level, early.level)
        XCTAssertEqual(later.pace, "Resting")
    }

    func testPaceWordsAreNeutral() {
        var days: [String: [ProgressTrack: Int]] = [:]
        // Earlier: 3 active days a week for four weeks.
        for w in 0..<4 { for d in 0..<3 { days[date("2026-10-01").addingTimeInterval(Double(w * 7 + d) * 86400).dayStr(cal)] = [.claude: 3] } }
        let now = date("2026-11-05")
        let words = Set(["Getting started", "Resting", "Above your usual", "On pace", "Light week"])
        XCTAssertTrue(words.contains(ProgressEngine.summary(state(days), now: now, calendar: cal).pace))
        XCTAssertEqual(ProgressEngine.summary(ProgressState(), now: now, calendar: cal).pace, "Getting started")
    }

    func testStagesMap() {
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 9, 10].map { ProgressEngine.stage(forLevel: $0) }, [1, 1, 2, 2, 3, 3, 4, 4, 5])
    }

    func testStoreRoundTripPermissionsAndCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("prog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProgressStore(url: dir.appendingPathComponent("progress.json"))
        var s = ProgressState()
        ProgressEngine.record(.claude, key: "x", at: date("2026-11-05"), state: &s)
        store.save(s)
        XCTAssertEqual(store.load(), s)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data("not json".utf8).write(to: store.url)
        XCTAssertEqual(store.load(), ProgressState(), "corrupt file yields a fresh state")
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(left.contains { $0.hasPrefix("progress.corrupt-") }, "and is kept aside, not deleted")
    }
}

private extension Date {
    func dayStr(_ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
