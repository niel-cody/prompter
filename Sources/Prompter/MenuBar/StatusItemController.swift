import AppKit

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
    @objc private func quit() { NSApp.terminate(nil) }
}
