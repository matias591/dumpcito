import XCTest
@testable import BuddyCapture

final class CaptureSupportTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("buddy-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testTimestampFormat() {
        let utc = TimeZone(identifier: "UTC")!
        // 2026-11-03 09:05:07 UTC
        let d = Date(timeIntervalSince1970: 1_793_696_707)
        let ts = CaptureSupport.timestamp(d, timeZone: utc)
        XCTAssertEqual(ts.count, 15)
        XCTAssertNotNil(ts.range(of: #"^\d{8}-\d{6}$"#, options: .regularExpression))
        XCTAssertEqual(CaptureSupport.timestamp(Date(timeIntervalSince1970: 0), timeZone: utc), "19700101-000000")
    }

    func testCaptureURLNamingAndCollision() {
        let utc = TimeZone(identifier: "UTC")!
        let d = Date(timeIntervalSince1970: 86_400 + 3_661) // 1970-01-02 01:01:01
        let first = CaptureSupport.captureURL(in: tmp, date: d, timeZone: utc)
        XCTAssertEqual(first.lastPathComponent, "19700102-010101.png")
        try? Data().write(to: first)
        let second = CaptureSupport.captureURL(in: tmp, date: d, timeZone: utc)
        XCTAssertEqual(second.lastPathComponent, "19700102-010101-2.png")
    }

    func testScaledSize() {
        XCTAssertTrue(CaptureSupport.scaledSize(width: 3600, height: 2000) == (1800, 1000))
        XCTAssertTrue(CaptureSupport.scaledSize(width: 1000, height: 3600) == (500, 1800))
        XCTAssertTrue(CaptureSupport.scaledSize(width: 1800, height: 1200) == (1800, 1200)) // exactly at limit
        XCTAssertTrue(CaptureSupport.scaledSize(width: 1280, height: 800) == (1280, 800))   // no upscale
        XCTAssertTrue(CaptureSupport.scaledSize(width: 5120, height: 2880) == (1800, 1013))
        let tiny = CaptureSupport.scaledSize(width: 100_000, height: 1)
        XCTAssertEqual(tiny.width, 1800); XCTAssertEqual(tiny.height, 1)
    }

    func testPruneRemovesOnlyOldPNGs() throws {
        let now = Date()
        func make(_ name: String, age: TimeInterval) throws -> URL {
            let u = tmp.appendingPathComponent(name)
            try Data([1]).write(to: u)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: u.path)
            return u
        }
        let old = try make("old.png", age: 25 * 3600)
        let edge = try make("fresh.png", age: 23 * 3600)
        let oldTxt = try make("old.txt", age: 48 * 3600)

        XCTAssertEqual(CaptureSupport.prune(dir: tmp, now: now), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: edge.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldTxt.path))
    }

    func testPruneMissingDirIsNoop() {
        XCTAssertEqual(CaptureSupport.prune(dir: tmp.appendingPathComponent("nope"), now: Date()), 0)
    }

    func testDefaultBaseDirSuffix() {
        XCTAssertTrue(CaptureSupport.defaultBaseDir().path.hasSuffix("Dumpcito/captures"))
    }
}
