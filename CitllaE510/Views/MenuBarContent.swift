import AppKit
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var eventTap: EventTapService
    @EnvironmentObject private var loginItem: LoginItemManager
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
            Text(error)
        } else {
            Text(eventTap.isRunning ? "Event tap active" : "Event tap inactive")
        }

        Divider()

        SettingsLink {
            Label("Settings…", systemImage: "gearshape")
        }

        Button("Diagnostics…") {
            openWindow(id: "diagnostics")
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
    }
}
