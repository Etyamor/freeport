import AppKit
import SwiftUI
import Combine
import FreePortKit

/// Owns the menu bar item and its popover.
///
/// This is AppKit rather than SwiftUI's `MenuBarExtra(.window)` on purpose:
/// that scene type sizes its window once and never shrinks it again, so
/// collapsing a group left a block of empty space below the content.
/// `NSPopover` follows `preferredContentSize` in both directions.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store = PortStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()

        let host = NSHostingController(rootView: ContentView().environmentObject(store))
        // Keeps preferredContentSize in sync with the SwiftUI ideal size, which
        // is what lets the popover track the content as rows come and go.
        host.sizingOptions = [.preferredContentSize]

        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: "Ports")
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(togglePopover)
        }

        store.$entries
            .combineLatest(store.$showCountInMenuBar)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateTitle() }
            .store(in: &cancellables)
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let count = store.devPortCount
        button.title = (store.showCountInMenuBar && count > 0) ? " \(count)" : ""
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // The popover steals focus properly only once it's on screen.
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
