import AppKit
import ApplicationServices
import Foundation
import os

/// The Dock's own entry points for Mission Control, App Exposé, Show Desktop
/// and Launchpad.
///
/// Posting the equivalent keystrokes (⌃↑, ⌃↓, F11, F4) does not work. The
/// WindowServer matches symbolic hotkeys against real HID events, so synthetic
/// ones are dropped no matter which event source or tap they are posted to -
/// `⌘⇧3` works because screenshots are not a symbolic hotkey. The Dock takes
/// requests instead:
///
/// - `CoreDockSendNotification` for Mission Control, Show Desktop and Launchpad.
///   It lives in ApplicationServices on macOS 26+, where `CoreDock.framework`
///   no longer exists.
/// - The `AXShowExpose` accessibility action on an app's Dock tile for App
///   Exposé. `com.apple.expose.front.awake` is still in the Dock's binary but
///   no longer does anything.
enum DockControl {
    private static let logger = Logger(subsystem: "com.ericng.citillae510", category: "dock")

    /// Calls the Dock's private `CoreDockSendNotification`.
    static func sendNotification(_ name: String) {
        typealias SendNotification = @convention(c) (CFString) -> Void

        var symbol: UnsafeMutableRawPointer?
        for path in [
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            "/System/Library/PrivateFrameworks/CoreDock.framework/CoreDock"
        ] {
            if let handle = dlopen(path, RTLD_NOW), let found = dlsym(handle, "CoreDockSendNotification") {
                symbol = found
                break
            }
        }
        guard let symbol else {
            logger.error("CoreDockSendNotification not found")
            return
        }
        unsafeBitCast(symbol, to: SendNotification.self)(name as CFString)
    }

    /// Shows every window of the frontmost application.
    ///
    /// App Exposé is per-app and the Dock only offers it per tile, so this
    /// presses `AXShowExpose` on the tile for the frontmost app. Apps that are
    /// not in the Dock fall back to the (now inert) notification.
    static func showAppExpose() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            sendNotification("com.apple.expose.front.awake")
            return
        }

        let root = AXUIElementCreateApplication(dock.processIdentifier)
        guard let tile = applicationTile(in: root, for: front) else {
            logger.notice("No Dock tile for \(front.localizedName ?? "?", privacy: .public); falling back to the notification")
            sendNotification("com.apple.expose.front.awake")
            return
        }

        let result = AXUIElementPerformAction(tile, "AXShowExpose" as CFString)
        if result != .success {
            logger.error("AXShowExpose failed: \(result.rawValue)")
        }
    }

    private static func applicationTile(in root: AXUIElement, for app: NSRunningApplication) -> AXUIElement? {
        var tiles: [AXUIElement] = []

        func collect(_ element: AXUIElement, _ depth: Int) {
            guard depth <= 4 else { return }
            var subrole: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            if subrole as? String == "AXApplicationDockItem" {
                tiles.append(element)
                return
            }
            var kids: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &kids) == .success,
                  let children = kids as? [AXUIElement] else { return }
            for child in children { collect(child, depth + 1) }
        }
        collect(root, 0)

        // Two tiles can share a name - a Chrome app and a native app both called
        // "Muse", say - so match the bundle URL first and the name second.
        if let bundleURL = app.bundleURL?.standardizedFileURL,
           let match = tiles.first(where: { tileURL($0)?.standardizedFileURL == bundleURL }) {
            return match
        }
        guard let name = app.localizedName else { return nil }
        return tiles.first { tileTitle($0) == name }
    }

    private static func tileURL(_ tile: AXUIElement) -> URL? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(tile, kAXURLAttribute as CFString, &value) == .success else { return nil }
        return value as? URL
    }

    private static func tileTitle(_ tile: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(tile, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
