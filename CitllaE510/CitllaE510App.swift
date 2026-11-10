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

    private init() {
        let store = ConfigStore()
        let tagger = MouseKeyTagger()
        config = store
        self.tagger = tagger
        eventTap = EventTapService(config: store, tagger: tagger)
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
        } label: {
            MenuBarLabel()
        }

        Window("Citlla E510", id: AppWindowID.main) {
            MainWindowView()
                .environmentObject(config)
                .environmentObject(eventTap)
                .environmentObject(loginItem)
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
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "computermouse")
            .accessibilityLabel("Citlla E510")
            .onAppear {
                WindowManager.shared.register(openWindow: openWindow)
            }
    }
}
