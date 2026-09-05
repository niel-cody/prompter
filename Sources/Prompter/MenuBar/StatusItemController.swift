import AppKit
import PrompterCore

/// The menu-bar presence. Deliberately small: this is a utility, not a control room.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let prompt: PromptController
    private let updates: UpdateChecker
    var openLibrary: (() -> Void)?
    var openSettings: (() -> Void)?

    init(prompt: PromptController, updates: UpdateChecker) {
        self.prompt = prompt
        self.updates = updates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Prompter")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Prompter"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let release = updates.available {
            menu.addItem(item("Update to Prompter \(release.version)…", #selector(offerUpdate), key: ""))
            menu.addItem(.separator())
        }
        menu.addItem(item("New Prompt…", #selector(newPrompt), key: "n"))
        menu.addItem(item("Prompt Clipboard", #selector(promptClipboard), key: "v", modifiers: [.command, .option]))
        let recent = NSMenuItem(title: "Recent Prompts", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        let recents = prompt.library?.recentDocuments(limit: 6) ?? []
        if recents.isEmpty {
            let none = NSMenuItem(title: "No Recent Prompts", action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentMenu.addItem(none)
        }
        for doc in recents {
            let mi = NSMenuItem(title: doc.title, action: #selector(presentRecent(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = doc.id.uuidString
            recentMenu.addItem(mi)
        }
        recentMenu.addItem(.separator())
        recentMenu.addItem(item("Sample Script", #selector(showSample), key: ""))
        recent.submenu = recentMenu
        menu.addItem(recent)
        menu.addItem(.separator())

        let toggle = item(prompt.isVisible ? "Hide Prompt" : "Show Prompt", #selector(toggleVisibility), key: "p", modifiers: [.command, .option])
        menu.addItem(toggle)
        menu.addItem(item("Snap to Camera", #selector(recenter), key: ""))
        menu.addItem(.separator())
        let running = prompt.session.isRunning
        menu.addItem(item(running ? "Pause" : "Start", #selector(toggleRunning), key: "\r", modifiers: [.command, .option]))
        menu.addItem(item("Restart", #selector(restart), key: "r", modifiers: [.command, .option]))
        menu.addItem(item("End Session & Review", #selector(endSession), key: ".", modifiers: [.command, .option]))
        let voiceItem = item("Voice Follow", #selector(toggleVoice), key: "")
        voiceItem.state = prompt.voice.isEnabled ? .on : .off
        menu.addItem(voiceItem)
        let styleItem = NSMenuItem(title: "Delivery", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for style in DeliveryStyle.allCases {
            let mi = NSMenuItem(title: style.displayName, action: #selector(pickStyle(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = style.rawValue
            mi.state = prompt.session.style == style ? .on : .off
            styleMenu.addItem(mi)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in ReadingMode.allCases {
            let mi = NSMenuItem(title: mode.displayName, action: #selector(pickMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode.rawValue
            mi.state = prompt.session.mode == mode ? .on : .off
            modeMenu.addItem(mi)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        menu.addItem(.separator())
        menu.addItem(item("Open Prompter", #selector(openLibraryWindow), key: "o"))
        menu.addItem(item("Settings…", #selector(openSettingsWindow), key: ","))
        let check = item("Check for Updates…", #selector(checkForUpdates), key: "")
        check.isEnabled = !updates.isChecking
        menu.addItem(check)
        menu.addItem(.separator())

        menu.addItem(item("Quit Prompter", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String, modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func promptClipboard() { prompt.promptClipboard() }
    @objc private func newPrompt() { prompt.library?.createNew(); openLibrary?() }
    @objc private func presentRecent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw),
              let doc = prompt.library?.document(id: id) else { return }
        prompt.present(doc)
    }
    @objc private func pickMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = ReadingMode(rawValue: raw) { prompt.setMode(mode) }
    }
    @objc private func openLibraryWindow() { openLibrary?() }
    @objc private func checkForUpdates() { Task { await updates.checkNow() } }
    @objc private func offerUpdate() { updates.offerAvailable() }
    @objc private func openSettingsWindow() { openSettings?() }
    @objc private func showSample() { prompt.present(text: SampleScript.text, title: "Sample") }
    @objc private func toggleVisibility() { prompt.toggleVisibility() }
    @objc private func recenter() { prompt.recenterUnderCamera() }
    @objc private func toggleRunning() { prompt.session.toggleRunning() }
    @objc private func restart() { prompt.session.reset() }
    @objc private func endSession() { prompt.endSession() }
    @objc private func toggleVoice() { prompt.setVoiceFollow(!prompt.voice.isEnabled) }
    @objc private func pickStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = DeliveryStyle(rawValue: raw) {
            prompt.setStyle(style)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
