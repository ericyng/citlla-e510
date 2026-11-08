import AppKit
import SwiftUI

/// Owns the Settings and Diagnostics windows.
///
/// The app is a menu bar utility (`LSUIElement`), so it has no Dock icon and
/// SwiftUI never opens a window on its own. Running from Xcode would otherwise
/// look like nothing happened, so the app delegate shows Settings on first run
/// and whenever Accessibility still needs to be granted.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var config: ConfigStore?
    private var eventTap: EventTapService?
    private var loginItem: LoginItemManager?

    private var settingsWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?

    private init() {}

    func configure(config: ConfigStore, eventTap: EventTapService, loginItem: LoginItemManager) {
        self.config = config
        self.eventTap = eventTap
        self.loginItem = loginItem
    }

    func showSettings(tab: SettingsTab = .buttons) {
        if let window = settingsWindow, window.isVisible {
            present(window)
            return
        }
        guard let view = makeSettingsView(tab: tab) else { return }
        let window = makeWindow(title: "Citlla E510 Settings", content: view, size: NSSize(width: 760, height: 560))
        settingsWindow = window
        present(window)
    }

    func showDiagnostics() {
        if let window = diagnosticsWindow {
            present(window)
            return
        }
        guard let view = makeDiagnosticsView() else { return }
        let window = makeWindow(title: "Citlla E510 Diagnostics", content: view, size: NSSize(width: 820, height: 560))
        diagnosticsWindow = window
        present(window)
    }

    private func makeSettingsView(tab: SettingsTab) -> AnyView? {
        guard let config, let eventTap, let loginItem else { return nil }
        return AnyView(
            SettingsView(initialTab: tab)
                .environmentObject(config)
                .environmentObject(eventTap)
                .environmentObject(loginItem)
        )
    }

    private func makeDiagnosticsView() -> AnyView? {
        guard let config, let eventTap, let loginItem else { return nil }
        return AnyView(
            DiagnosticsView()
                .environmentObject(config)
                .environmentObject(eventTap)
                .environmentObject(loginItem)
        )
    }

    private func makeWindow<Content: View>(title: String, content: Content, size: NSSize) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
