import AppKit
import SwiftUI

/// Owns the Settings and Diagnostics windows.
///
/// The app is a menu bar utility (`LSUIElement`), so it has no Dock icon and
/// SwiftUI never opens a window on its own. Running from Xcode would otherwise
/// look like nothing happened, so the app delegate shows Settings on first run
/// and whenever Accessibility still needs to be granted.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var config: ConfigStore?
    private var eventTap: EventTapService?
    private var loginItem: LoginItemManager?

    private var settingsWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?
    private var testerWindow: NSWindow?
    private var tester: ButtonTester?

    private override init() {
        super.init()
    }

    func configure(config: ConfigStore, eventTap: EventTapService, loginItem: LoginItemManager) {
        self.config = config
        self.eventTap = eventTap
        self.loginItem = loginItem
    }

    /// Settings is a fixed-size window: the mouse diagram and the nine rows are
    /// laid out to fit exactly, so the window is not resizable.
    static let settingsSize = NSSize(width: 860, height: 720)

    func showSettings(tab: SettingsTab = .mouse) {
        if let window = settingsWindow, window.isVisible {
            present(window)
            return
        }
        guard let view = makeSettingsView(tab: tab) else { return }
        let window = makeWindow(title: "Citlla E510 Settings", content: view, size: Self.settingsSize)
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

    func showTester() {
        if let window = testerWindow {
            tester?.start()
            present(window)
            return
        }
        guard let config else { return }
        let tester = ButtonTester(config: config)
        self.tester = tester
        let window = makeWindow(
            title: "Citlla E510 Button Tester",
            content: TesterView(tester: tester, action: { control in
                guard let button = control.hidButtons.first else { return nil }
                return config.binding(for: button).action
            }),
            size: NSSize(width: 940, height: 720)
        )
        window.delegate = self
        testerWindow = window
        present(window)
        tester.start()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === testerWindow {
            tester?.stop()
        }
    }

    private func makeSettingsView(tab: SettingsTab) -> AnyView? {
        guard let config, let eventTap, let loginItem else { return nil }
        return AnyView(
            SettingsView(initialTab: tab)
                // Pin the size so the hosting controller does not shrink the
                // window back to the tab's own preferred height on first layout.
                .frame(width: Self.settingsSize.width, height: Self.settingsSize.height)
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
