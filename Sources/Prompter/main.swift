import AppKit

// Prompter is a menu-bar utility (LSUIElement) with floating panels, so it drives
// NSApplication directly rather than through the SwiftUI App lifecycle.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
