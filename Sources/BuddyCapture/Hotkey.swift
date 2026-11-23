import Carbon.HIToolbox
import Foundation

enum HotkeyEdge: Sendable { case pressed, released }

/// Injectable so tests never touch Carbon.
protocol HotkeyRegistering: AnyObject {
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @Sendable (HotkeyEdge) -> Void) throws
    func unregister()
}

/// Carbon RegisterEventHotKey: no Accessibility permission needed; gives press and release.
/// Needs a running app event loop (NSApplication) to deliver events.
final class CarbonHotkeyRegistrar: HotkeyRegistering {
    private final class Box { let handler: @Sendable (HotkeyEdge) -> Void; init(_ h: @escaping @Sendable (HotkeyEdge) -> Void) { handler = h } }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var box: Unmanaged<Box>?

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @Sendable (HotkeyEdge) -> Void) throws {
        unregister()
        let retained = Unmanaged.passRetained(Box(handler))
        box = retained

        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let box = Unmanaged<Box>.fromOpaque(userData).takeUnretainedValue()
            switch GetEventKind(event) {
            case UInt32(kEventHotKeyPressed): box.handler(.pressed)
            case UInt32(kEventHotKeyReleased): box.handler(.released)
            default: return OSStatus(eventNotHandledErr)
            }
            return noErr
        }
        var status = InstallEventHandler(GetApplicationEventTarget(), callback, types.count, &types,
                                         retained.toOpaque(), &handlerRef)
        guard status == noErr else { cleanup(); throw CaptureError.hotkeyRegistration(status) }

        let id = EventHotKeyID(signature: OSType(0x4244_4459) /* 'BDDY' */, id: 1)
        status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else { cleanup(); throw CaptureError.hotkeyRegistration(status) }
    }

    func unregister() { cleanup() }

    private func cleanup() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
        box?.release(); box = nil
    }

    deinit { cleanup() }
}
