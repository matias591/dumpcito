import AppKit
import SwiftUI

/// Review window for every BuddyUI state, in dark and light.
///
///   BuddyUIGallery                 interactive (sidebar, live demo, cycle toggle)
///   BuddyUIGallery --state picker  open on one state (raw value, see GalleryState)
///   BuddyUIGallery --shoot DIR     capture every state with screencapture, then quit
///   BuddyUIGallery --film DIR      capture frame bursts of the scripted demo's transitions, then quit
@main
enum GalleryMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = GalleryDelegate(arguments: CommandLine.arguments)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class GalleryDelegate: NSObject, NSApplicationDelegate {
    private let controller = GalleryController()
    private var window: NSWindow?
    private let shootDir: URL?
    private let filmDir: URL?

    init(arguments: [String]) {
        if let i = arguments.firstIndex(of: "--shoot"), i + 1 < arguments.count {
            shootDir = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
        } else {
            shootDir = nil
        }
        if let i = arguments.firstIndex(of: "--film"), i + 1 < arguments.count {
            filmDir = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
        } else {
            filmDir = nil
        }
        if let i = arguments.firstIndex(of: "--state"), i + 1 < arguments.count,
           let s = GalleryState(rawValue: arguments[i + 1]) {
            controller.state = s
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if shootDir != nil {
            controller.showSidebar = false
            controller.state = .idle
        }
        if filmDir != nil {
            controller.showSidebar = false
            controller.state = .demo
        }
        let hosting = NSHostingController(rootView: GalleryRoot(controller: controller))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Dumpcito UI Gallery"
        window.styleMask.insert(.resizable)
        window.center()
        if shootDir != nil || filmDir != nil, let retina = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }) {
            // Shoot on a 2x screen so captures show real hairlines.
            let f = retina.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.midX - window.frame.width / 2, y: f.midY - window.frame.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        print("gallery window id \(window.windowNumber)")

        if let dir = shootDir {
            Task { await shoot(into: dir, window: window) }
        }
        if let dir = filmDir {
            Task { await film(into: dir, window: window) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Bursts around the demo's transitions (times from Fake.runDemo, approximate).
    private func film(into dir: URL, window: NSWindow) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let t0 = Date()
        let windows: [(String, Double, Double)] = [
            ("meeting-in", 4.7, 6.2), ("picker-in", 15.0, 16.2), ("needsyou-hop", 22.5, 23.8), ("expand", 26.0, 27.2),
        ]
        var n = 0
        for (label, from, to) in windows {
            while Date().timeIntervalSince(t0) < from { try? await Task.sleep(for: .milliseconds(20)) }
            while Date().timeIntervalSince(t0) < to {
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                n += 1
                await captureAsync(window.windowNumber,
                                   to: dir.appendingPathComponent(String(format: "%03d", n) + "-\(label)-\(ms)ms.jpg").path)
            }
        }
        NSApp.terminate(nil)
    }

    /// Runs screencapture without blocking the main thread, so animations keep running.
    private func captureAsync(_ windowNumber: Int, to path: String) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-t", "jpg", "-l", "\(windowNumber)", path]
            p.terminationHandler = { _ in done.resume() }
            do { try p.run() } catch { done.resume() }
        }
    }

    private func shoot(into dir: URL, window: NSWindow) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(1.5))
        let states = GalleryState.allCases.filter { $0 != .demo }
        for (i, state) in states.enumerated() {
            controller.state = state
            try? await Task.sleep(for: .seconds(1.2))
            let name = String(format: "%02d", i + 1) + "-\(state.rawValue).png"
            let path = dir.appendingPathComponent(name).path
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", path]
            do {
                try p.run()
                p.waitUntilExit()
                print("shot \(name) status \(p.terminationStatus)")
            } catch {
                print("screencapture failed: \(error)")
            }
        }
        NSApp.terminate(nil)
    }
}
