import SwiftUI
import AppKit
import FreePortKit

@main
struct FreePortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { CLI.handleIfNeeded() }

    var body: some Scene {
        // The UI lives entirely in the status item; this scene just satisfies
        // the App protocol and never shows (the bundle is LSUIElement).
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = StatusItemController()
    }
}
