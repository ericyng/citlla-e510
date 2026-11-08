import SwiftUI

@main
@MainActor
struct CitllaE510App: App {
    @StateObject private var config: ConfigStore
    @StateObject private var eventTap: EventTapService
    @StateObject private var loginItem = LoginItemManager.shared

    init() {
        let store = ConfigStore()
        let tap = EventTapService(config: store)
        _config = StateObject(wrappedValue: store)
        _eventTap = StateObject(wrappedValue: tap)

        // Let AppKit finish launching before creating the session event tap.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            tap.startIfNeeded()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(config)
                .environmentObject(eventTap)
                .environmentObject(loginItem)
        } label: {
            Label("Citlla E510", systemImage: "computermouse")
        }

        Settings {
            SettingsView()
                .environmentObject(config)
                .environmentObject(eventTap)
                .environmentObject(loginItem)
        }

        Window("Citlla E510 Diagnostics", id: "diagnostics") {
            DiagnosticsView()
                .environmentObject(config)
                .environmentObject(eventTap)
                .environmentObject(loginItem)
        }
        .defaultSize(width: 820, height: 560)
    }
}
