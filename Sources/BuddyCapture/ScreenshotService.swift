import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

protocol ScreenshotTaking: Sendable {
    /// Captures the display under the mouse, saves a PNG, returns its URL.
    func capture() async throws -> URL
}

/// ScreenCaptureKit screenshot of the display containing the cursor, excluding Buddy's own windows.
/// Verified by compilation only (needs Screen Recording TCC + an app bundle).
struct ScreenshotService: ScreenshotTaking {
    let baseDir: URL
    let bundleID: String?

    init(baseDir: URL = CaptureSupport.defaultBaseDir(), bundleID: String? = Bundle.main.bundleIdentifier) {
        self.baseDir = baseDir
        self.bundleID = bundleID
    }

    func capture() async throws -> URL {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.screenRecordingMissing }

        let fm = FileManager.default
        try fm.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let now = Date()
        CaptureSupport.prune(dir: baseDir, now: now)

        // Display under the cursor (NSScreen uses Cocoa coords, same as NSEvent.mouseLocation).
        let mouse = NSEvent.mouseLocation
        let screen = await MainActor.run { () -> (id: CGDirectDisplayID, scale: CGFloat)? in
            let s = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            guard let s, let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (num.uint32Value, s.backingScaleFactor)
        }

        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { throw CaptureError.screenshot(error.localizedDescription) }

        guard let display = content.displays.first(where: { $0.displayID == screen?.id }) ?? content.displays.first else {
            throw CaptureError.screenshot("no display found")
        }
        let excluded: [SCRunningApplication]
        if let bundleID { excluded = content.applications.filter { $0.bundleIdentifier == bundleID } } else { excluded = [] }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])

        let scale = Double(screen?.scale ?? 2)
        let target = CaptureSupport.scaledSize(width: Int(Double(display.width) * scale),
                                               height: Int(Double(display.height) * scale))
        let config = SCStreamConfiguration()
        config.width = target.width
        config.height = target.height
        config.showsCursor = true

        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
        catch { throw CaptureError.screenshot(error.localizedDescription) }

        let url = CaptureSupport.captureURL(in: baseDir, date: now)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError.screenshot("cannot create PNG at \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError.screenshot("PNG encode failed") }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}
