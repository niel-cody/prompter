import AppKit
import PrompterCore

/// The menu-bar presence. Deliberately small: this is a utility, not a control room.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let prompt: PromptController

    init(prompt: PromptController) {
        self.prompt = prompt
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

        menu.addItem(item("Prompt Clipboard", #selector(promptClipboard), key: "v", modifiers: [.command, .option]))
        menu.addItem(item("Sample Script", #selector(showSample), key: ""))
        menu.addItem(.separator())

        let toggle = item(prompt.isVisible ? "Hide Prompt" : "Show Prompt", #selector(toggleVisibility), key: "p", modifiers: [.command, .option])
        menu.addItem(toggle)
        menu.addItem(item("Snap to Camera", #selector(recenter), key: ""))
        menu.addItem(.separator())
        let running = prompt.session.isRunning
        menu.addItem(item(running ? "Pause" : "Start", #selector(toggleRunning), key: "\r", modifiers: [.command, .option]))
        menu.addItem(item("Restart", #selector(restart), key: "r", modifiers: [.command, .option]))
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
    @objc private func showSample() { prompt.present(text: SampleScript.text, title: "Sample") }
    @objc private func toggleVisibility() { prompt.toggleVisibility() }
    @objc private func recenter() { prompt.recenterUnderCamera() }
    @objc private func toggleRunning() { prompt.session.toggleRunning() }
    @objc private func restart() { prompt.session.reset() }
    @objc private func pickStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = DeliveryStyle(rawValue: raw) {
            prompt.session.setStyle(style)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
