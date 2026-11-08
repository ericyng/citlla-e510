import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The XCTest bundle is injected into this app as its test host; skip the
        // menu bar plumbing and the event tap while tests run.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard !Snapshot.runIfRequested() else { return }

        let model = AppModel.shared

        Task { @MainActor in
            // Let AppKit finish launching before creating the session event tap.
            try? await Task.sleep(for: .milliseconds(400))
            model.eventTap.startIfNeeded()

            // A freshly installed (ad hoc) build can be reported as untrusted
            // for a moment before macOS re-validates the existing grant, so
            // keep trying quietly for a minute instead of giving up.
            for _ in 0..<30 where !model.eventTap.isRunning {
                try? await Task.sleep(for: .seconds(2))
                model.eventTap.startIfNeeded()
            }

            // Nothing is visible until the menu bar icon is clicked, so show the
            // window when there is something to act on.
            if !model.config.hadStoredConfig || !PermissionManager.hasAccessibility {
                WindowManager.shared.showSettings(tab: .permissions)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
