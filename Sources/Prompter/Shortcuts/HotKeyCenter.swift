import AppKit
import Carbon.HIToolbox

/// A global shortcut the user can trigger while any other app is focused.
struct HotKey: Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let promptClipboard = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey))
    static let toggleVisibility = HotKey(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey))
    static let startPause = HotKey(keyCode: UInt32(kVK_Return), modifiers: UInt32(cmdKey | optionKey))
    static let nextPhrase = HotKey(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey | optionKey))
    static let previousPhrase = HotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey | optionKey))
    static let nextSection = HotKey(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(cmdKey | optionKey))
    static let previousSection = HotKey(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(cmdKey | optionKey))
    static let endSession = HotKey(keyCode: UInt32(kVK_ANSI_Period), modifiers: UInt32(cmdKey | optionKey))
    static let fontLarger = HotKey(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(cmdKey | optionKey))
    static let fontSmaller = HotKey(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt32(cmdKey | optionKey))
}

/// Registers system-wide hot keys with Carbon's `RegisterEventHotKey`, which works without
/// Accessibility permission and while Zoom, Teams, Chrome or Keynote have focus.
@MainActor
final class HotKeyCenter {
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    var registeredCount: Int { refs.count }

    // Carbon hands us a C callback with no closure context, so route through a single
    // shared instance.
    nonisolated(unsafe) private static var shared: HotKeyCenter?

    init() {
        Self.shared = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            Task { @MainActor in HotKeyCenter.shared?.fire(id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    func register(_ hotKey: HotKey, handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052_4D50) /* 'PRMP' */, id: id)
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Prompter: failed to register hot key (\(status))")
            return
        }
        handlers[id] = handler
        refs[id] = ref
    }

    func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    private func fire(_ id: UInt32) { handlers[id]?() }
}
