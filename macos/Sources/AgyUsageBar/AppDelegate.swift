import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let manager = UsageManager()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var anchor: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(toggle(_:))
        }
        apply(manager.bar)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(m: manager))
        manager.$bar
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.apply($0) }
            .store(in: &cancellables)
        manager.start()
        if CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.show() }
        }
    }

    private func apply(_ bar: BarState) {
        guard let button = statusItem.button else { return }
        if let fraction = bar.fraction {
            button.image = MenuBarIcon.ring(used: fraction, color: bar.band.nsColor)
        } else if let symbol = bar.symbol {
            button.image = MenuBarIcon.symbol(symbol)
        } else {
            button.image = nil
        }
        button.title = bar.text
        button.imagePosition = bar.text.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = bar.tooltip
        button.setAccessibilityLabel(bar.tooltip)
    }

    @objc private func toggle(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) } else { show() }
    }

    private func show() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        manager.refreshIfStale()
        let screen = buttonWindow.screen ?? NSScreen.main
        let center = CGPoint(x: buttonWindow.frame.midX, y: buttonWindow.frame.midY)
        if let screen, screen.frame.contains(center) {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else if let screen {
            // The menu bar is hidden (full-screen app), so the status item sits above the screen edge and a popover
            // anchored to it would open with its top cut off. Anchor to a 1-point window at the top right instead.
            let visible = screen.visibleFrame
            let window = anchor ?? makeAnchor()
            window.setFrame(NSRect(x: visible.maxX - 48, y: visible.maxY - 1, width: 1, height: 1), display: false)
            window.orderFrontRegardless()
            if let view = window.contentView { popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY) }
        }
        keepOnScreen()
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makeAnchor() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        anchor = window
        return window
    }

    /// Safety net: never leave any part of the popover outside the visible screen area.
    private func keepOnScreen() {
        guard let window = popover.contentViewController?.view.window,
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        if frame.maxY > visible.maxY + 3 { frame.origin.y = visible.maxY - frame.height }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width - 6 }
        if frame.minX < visible.minX { frame.origin.x = visible.minX + 6 }
        if frame.origin != window.frame.origin { window.setFrameOrigin(frame.origin) }
    }

    func popoverDidClose(_ notification: Notification) {
        anchor?.orderOut(nil)
    }
}
