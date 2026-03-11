import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
delegate.buildMainMenu()
app.run()
