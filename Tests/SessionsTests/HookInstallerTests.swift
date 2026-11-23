import XCTest
@testable import BuddyCore
@testable import BuddySessions

final class HookInstallerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("hooktest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private var settings: URL { dir.appendingPathComponent("settings.json") }
    private func installer(_ exe: String = "/Applications/Dumpcito.app/Contents/MacOS/Dumpcito") -> HookInstaller {
        HookInstaller(tool: .claude, configURL: settings, executable: exe)
    }
    private func read() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    }

    func testInstallIntoMissingFile() throws {
        try installer().install()
        XCTAssertTrue(installer().isInstalled())
        let hooks = try read()["hooks"] as! [String: Any]
        XCTAssertEqual(Set(hooks.keys), Set(HookInstaller.events(for: .claude)))
    }

    func testInstallKeepsOtherHooksAndSettingsAndBacksUp() throws {
        let original = #"{"model":"x","hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"echo hi"}]}]}}"#
        try Data(original.utf8).write(to: settings)
        try installer().install()
        let root = try read()
        XCTAssertEqual(root["model"] as? String, "x")
        let stop = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2, "user's own Stop hook kept, ours appended")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("dumpcito-backup") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(backups[0])), original)
    }

    func testInstallIsIdempotentAndUpdatesPath() throws {
        try installer("/old/Dumpcito").install()
        try installer("/new/Dumpcito").install()
        let stop = (try read()["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 1)
        let cmd = ((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as! String)
        XCTAssertTrue(cmd.contains("/new/Dumpcito")); XCTAssertFalse(cmd.contains("/old/Dumpcito"))
    }

    func testLegacyBuddyEntriesAreReplacedNotDuplicated() throws {
        let legacy = #"{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"x # buddy-attention-hook"}]}]}}"#
        try Data(legacy.utf8).write(to: settings)
        try installer().install()
        let stop = (try read()["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 1)
        XCTAssertTrue(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as! String).contains("dumpcito-hook"))
    }

    func testUninstallRemovesOnlyOurs() throws {
        let original = #"{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"echo hi"}]}]}}"#
        try Data(original.utf8).write(to: settings)
        try installer().install()
        try installer().uninstall()
        XCTAssertFalse(installer().isInstalled())
        let hooks = try read()["hooks"] as! [String: Any]
        XCTAssertEqual(Array(hooks.keys), ["Stop"])
        XCTAssertEqual((hooks["Stop"] as! [[String: Any]]).count, 1)
    }

    func testRefusesCorruptSettingsAndLeavesThemAlone() throws {
        try Data("{ not json".utf8).write(to: settings)
        XCTAssertThrowsError(try installer().install())
        XCTAssertEqual(try String(contentsOf: settings), "{ not json")
        try Data("[1,2]".utf8).write(to: settings)
        XCTAssertThrowsError(try installer().install()) { XCTAssertEqual($0 as? HookInstallError, .settingsNotAnObject("settings.json")) }
    }

    func testCommandQuotesPathWithSpacesAndQuotes() {
        let cmd = installer("/Users/o'neil/My Apps/Dumpcito").command
        XCTAssertTrue(cmd.contains(#"'/Users/o'\''neil/My Apps/Dumpcito'"#))
        XCTAssertTrue(cmd.contains("--hook --tool claude"))
        XCTAssertTrue(cmd.hasSuffix("exit 0 # dumpcito-hook"))
    }

    // MARK: Codex and Cursor

    func testCodexUsesClaudeShapeAndItsOwnEvents() throws {
        let url = dir.appendingPathComponent("hooks.json")
        let inst = HookInstaller(tool: .codex, configURL: url, executable: "/x/Dumpcito")
        try inst.install()
        XCTAssertTrue(inst.isInstalled())
        let hooks = (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any])["hooks"] as! [String: Any]
        XCTAssertEqual(Set(hooks.keys), Set(HookInstaller.events(for: .codex)))
        let stop = hooks["Stop"] as! [[String: Any]]
        XCTAssertTrue(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as! String).contains("--hook --tool codex"))
    }

    func testCursorUsesFlatShapeVersionAndOnlySafeEvents() throws {
        let url = dir.appendingPathComponent("hooks.json")
        let original = #"{"version":1,"hooks":{"beforeShellExecution":[{"command":"./audit.sh"}],"stop":[{"command":"./mine.sh"}]}}"#
        try Data(original.utf8).write(to: url)
        let inst = HookInstaller(tool: .cursor, configURL: url, executable: "/x/Dumpcito")
        try inst.install()
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertEqual(root["version"] as? Int, 1)
        let hooks = root["hooks"] as! [String: Any]
        XCTAssertEqual(Set(hooks.keys), Set(HookInstaller.events(for: .cursor)).union(["beforeShellExecution"]))
        XCTAssertEqual((hooks["beforeShellExecution"] as! [[String: Any]]).count, 1, "user's permission hook untouched, none added")
        let stop = hooks["stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2)
        XCTAssertTrue((stop[1]["command"] as! String).contains("--hook --tool cursor"))
        try inst.uninstall()
        XCTAssertFalse(inst.isInstalled())
        let after = (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any])["hooks"] as! [String: Any]
        XCTAssertEqual(Set(after.keys), ["beforeShellExecution", "stop"])
    }

    func testToolsDoNotRecogniseEachOthersConfig() throws {
        let url = dir.appendingPathComponent("hooks.json")
        try HookInstaller(tool: .codex, configURL: url, executable: "/x/Dumpcito").install()
        XCTAssertFalse(HookInstaller(tool: .cursor, configURL: url, executable: "/x/Dumpcito").isInstalled())
    }

    func testToolPresenceFromHomeFolder() throws {
        XCTAssertFalse(HookInstaller.isToolPresent(.codex, home: dir, searchPath: []))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        XCTAssertTrue(HookInstaller.isToolPresent(.codex, home: dir, searchPath: []))
    }
}
