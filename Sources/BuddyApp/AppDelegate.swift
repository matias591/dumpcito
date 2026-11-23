import AppKit
import BuddyUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: BuddyController!
    private var statusItem: NSStatusItem!
    private var tour: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = BuddyController()
        buildStatusItem()
        controller.onShowTour = { [weak self] in self?.showTour() }
        controller.start()
        if !controller.hasOnboarded { showTour() }
    }

    private func showTour() {
        if let tour { tour.present(); return }
        let c = controller!
        let actions = OnboardingActions(
            connectTool: { c.connect($0) },
            refreshTools: { c.refreshTools() },
            allowCalendar: { await c.allowCalendar() },
            allowVoice: { await c.allowVoice() },
            finish: {})
        let window = OnboardingWindow(settings: c.settings, actions: actions) { [weak self] completed in
            if completed { c.hasOnboarded = true }
            c.startPermissionServices(promptForPermissions: false)
            self?.tour = nil
        }
        tour = window
        window.present()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "circle.grid.2x2", accessibilityDescription: "Dumpcito")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(statusClicked)
    }

    /// The menu bar icon opens the same menu as right-clicking the buddy. If the buddy is hidden, it comes back.
    @objc private func statusClicked() {
        guard let button = statusItem.button, let window = button.window else { return }
        if !controller.isVisible { controller.toggleVisible() }
        controller.showMenu(near: window.convertToScreen(button.convert(button.bounds, to: nil)))
    }
}
