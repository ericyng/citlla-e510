import AppKit
import SwiftUI

/// Owns the objects every scene and window shares. Created once so the app
/// delegate, the menu bar menu and the main window all talk to the same
/// `ConfigStore` and `EventTapService`.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let config: ConfigStore
    let eventTap: EventTapService
    let tagger: MouseKeyTagger
    let loginItem: LoginItemManager
    /// One frontmost-app cache shared by the event tap and the Overview. It is
    /// started by `AppDelegate`; before that it holds the app that was in front
    /// when the process launched.
    let activeApp: ActiveAppMonitor
    /// The mouse's battery level, read from the IORegistry. One instance so the
    /// menu bar and the Overview show the same reading.
    let battery: MouseBatteryMonitor

    private init() {
        let store = ConfigStore()
        let tagger = MouseKeyTagger()
        let activeApp = ActiveAppMonitor()
        config = store
        self.tagger = tagger
        self.activeApp = activeApp
        battery = MouseBatteryMonitor()
        eventTap = EventTapService(config: store, tagger: tagger, activeApp: activeApp)
        loginItem = LoginItemManager.shared
        WindowManager.shared.configure(
            config: store,
            eventTap: eventTap,
            tagger: tagger,
            loginItem: loginItem
        )
    }
}

@main
@MainActor
struct CitllaE510App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var config = AppModel.shared.config
    @ObservedObject private var eventTap = AppModel.shared.eventTap
    @ObservedObject private var loginItem = AppModel.shared.loginItem
    @ObservedObject private var activeApp = AppModel.shared.activeApp
    @ObservedObject private var battery = AppModel.shared.battery

    init() {
        StatusProbe.runIfRequested()
        _ = ActionProbe.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(config)
                .environmentObject(eventTap)
                .environmentObject(loginItem)
                .environmentObject(activeApp)
                .environmentObject(battery)
        } label: {
            MenuBarLabel()
        }

        Window("Citlla E510", id: AppWindowID.main) {
            MainWindowView()
                .environmentObject(config)
                .environmentObject(eventTap)
                .environmentObject(loginItem)
                .environmentObject(activeApp)
                .environmentObject(battery)
                .environmentObject(WindowManager.shared.state)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        // The app must still start as a menu bar utility with no window. The
        // window is only created when the menu bar, a command or the delegate
        // asks for it.
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Citlla E510") {
                    WindowManager.shared.showSettings(tab: .about)
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    WindowManager.shared.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// The menu bar icon. It also captures SwiftUI's `openWindow` action so the
/// AppDelegate and the menu bar menu can open the main window programmatically.
///
/// When Bluetooth reports a level the icon carries it as text, so the battery
/// is visible without opening the menu. The mouse icon stays first so the item
/// is still recognisable; a connection that reports nothing (the 2.4 GHz
/// receiver) shows the icon alone.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var battery = AppModel.shared.battery

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "computermouse")
            if let percent = battery.reading.percent {
                Text("\(percent)%")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(battery.reading.accessibilityText)
        .onAppear {
            WindowManager.shared.register(openWindow: openWindow)
        }
    }
}
