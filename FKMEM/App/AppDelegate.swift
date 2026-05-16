import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MemoryStore()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var idleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        store.refreshNow()
        startIdleRefresh()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: "memorychip",
            accessibilityDescription: "FKMEM"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.title = " —"
        button.font = .menuBarFont(ofSize: 0)
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        observeStoreForStatusItem()
    }

    private func observeStoreForStatusItem() {
        withObservationTracking {
            _ = store.snapshot.availableBytes
            _ = store.snapshot.pressure
            _ = store.lastUpdate
        } onChange: {
            Task { @MainActor [weak self] in
                self?.updateStatusItemText()
                self?.observeStoreForStatusItem()
            }
        }
    }

    private func updateStatusItemText() {
        guard let button = statusItem.button else { return }
        let bytes = store.snapshot.availableBytes
        button.title = " " + MemoryFormatter.formatCompact(bytes)

        let color: NSColor
        switch store.snapshot.pressure {
        case .normal: color = .labelColor
        case .warn: color = .systemYellow
        case .critical: color = .systemRed
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.menuBarFont(ofSize: 0)
        ]
        button.attributedTitle = NSAttributedString(string: button.title, attributes: attributes)
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)

        if isRight {
            showContextMenu(from: button)
        } else {
            togglePopover(from: button)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            startIdleRefresh()
        } else {
            store.refreshNow()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            store.startAutoRefresh(interval: 3)
            idleTimer?.invalidate()
        }
    }

    private func startIdleRefresh() {
        store.startAutoRefresh(interval: 15)
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let info = NSMenuItem(title: "FKMEM", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
