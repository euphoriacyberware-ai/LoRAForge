import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSDocumentController handles document lifecycle based on Info.plist
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }
}
