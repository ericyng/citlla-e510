import AppKit
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.ericng.citillae510", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The XCTest bundle is injected into this app as its test host; skip the
        // menu bar plumbing and the event tap while tests run.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard !Snapshot.runIfRequested() else { return }
        // `--perform`, `--post-shortcut` and `--coredock` are one-shot probes;
        // they exit on their own and must not also install the event tap or
        // open a window.
        guard !CommandLine.arguments.contains("--perform"),
              !CommandLine.arguments.contains("--post-shortcut"),
              !CommandLine.arguments.contains("--coredock") else { return }

        let model = AppModel.shared

        Task { @MainActor in
            // Let AppKit finish launching before creating the session event tap.
            try? await Task.sleep(for: .milliseconds(400))

            // The truth as this process sees it, which a `--status` run from a
            // terminal cannot report reliably: the terminal's own grants get
            // borrowed there.
            logger.notice("Launch: accessibility=\(PermissionManager.hasAccessibility, privacy: .public) inputMonitoring=\(PermissionManager.inputMonitoringStatusText, privacy: .public)")

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
