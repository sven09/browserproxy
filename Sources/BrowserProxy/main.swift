import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: no Dock icon, no menu bar, but the picker panel can still take focus.
app.setActivationPolicy(.accessory)
app.run()
