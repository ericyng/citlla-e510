import AppKit
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var eventTap: EventTapService
    @EnvironmentObject private var loginItem: LoginItemManager
    @EnvironmentObject private var battery: MouseBatteryMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle(
            "Enable Remapping",
            isOn: Binding(
                get: { config.config.enabled },
                set: { newValue in
                    config.config.enabled = newValue
                    if newValue { eventTap.startIfNeeded() }
                }
            )
        )

        if let error = eventTap.lastError, !eventTap.isRunning {
            HStack {
                Text(error)
                Spacer()
                Button("Retry") { eventTap.startIfNeeded() }
            }
        } else {
            Text(eventTap.isRunning ? "Event tap active" : "Event tap inactive")
        }

        // Read-only status. The menu bar label already carries the percentage
        // when there is one; this line explains the case where there is not.
        Label(battery.reading.summaryText, systemImage: battery.reading.symbolName)

        Divider()

        Button("Open Citlla E510…") {
            WindowManager.shared.showMain(section: .overview)
        }

        Button("Test Buttons…") {
            WindowManager.shared.showTester()
        }

        Button("Diagnostics…") {
            WindowManager.shared.showDiagnostics()
        }

        Divider()

        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            )
        )

        Divider()

        Button("Quit Citlla E510") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .onAppear {
            // Accessibility can be granted while the app is already running
            // (or just after a rebuild), so re-check every time the menu opens.
            eventTap.startIfNeeded()
            // The menu bar label normally hands this over at launch; registering
            // here as well covers a scene rebuild that never re-renders the
            // label.
            WindowManager.shared.register(openWindow: openWindow)
        }
    }
}
