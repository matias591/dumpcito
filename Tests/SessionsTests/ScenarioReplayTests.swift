import XCTest
import BuddyCore
@testable import BuddySessions

/// Replays every spec/scenarios/*.json through the real normalizer, state store and detector.
/// The Windows app runs the same files, so both apps behave identically.
final class ScenarioReplayTests: XCTestCase {
    private let base: Int64 = 1_800_000_000_000

    private var scenariosDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("spec/scenarios")
    }

    func testAllScenarios() throws {
        let files = try FileManager.default.contentsOfDirectory(at: scenariosDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(files.count, 16)
        for file in files { try replay(file) }
    }

    private func replay(_ file: URL) throws {
        let name = file.deletingPathExtension().lastPathComponent
        let scenario = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scn-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StateStore(dir: dir)
        var detector = SessionEventDetector(finishedThreshold: 20, attentionCooldown: 30)

        for raw in scenario["preseed"] as? [[String: Any]] ?? [] {
            var r = raw
            for k in ["at", "workingSince", "touched"] { if let v = r[k] as? Int64 ?? (r[k] as? Int).map(Int64.init) { r[k] = base + v } }
            let rec = try JSONDecoder().decode(StateRecord.self, from: JSONSerialization.data(withJSONObject: r))
            try store.write(rec)
        }
        _ = detector.ingest(store.readAll(), nowMs: base) // priming poll

        for (i, step) in (scenario["steps"] as! [[String: Any]]).enumerated() {
            let t = base + Int64(((step["t"] as? Double) ?? Double(step["t"] as! Int)) * 1000)
            let label = "\(name) step \(i)"
            if let tool = step["tool"] as? String, let payload = step["payload"] {
                let data = try JSONSerialization.data(withJSONObject: payload)
                AttentionHook.handle(tool: tool, input: data, store: store, now: Date(timeIntervalSince1970: Double(t) / 1000))
            }
            var got: [String] = []
            if step["noPoll"] as? Bool != true {
                got = detector.ingest(store.readAll(), nowMs: t).map { "\($0.kind.rawValue)|\($0.record.tool)|\($0.record.session)" }
            }
            let want = (step["expectEvents"] as? [[String: Any]] ?? []).map { "\($0["kind"]!)|\($0["tool"]!)|\($0["session"]!)" }
            XCTAssertEqual(got.sorted(), want.sorted(), "\(label): events")
            for (key, expected) in step["expectState"] as? [String: String] ?? [:] {
                let parts = key.components(separatedBy: "__")
                let rec = store.read(tool: parts[0], session: parts[1])
                let shown = rec.map { SessionEventDetector.displayState($0, nowMs: t).rawValue } ?? "absent"
                XCTAssertEqual(shown, expected, "\(label): state of \(key)")
            }
        }
    }
}
