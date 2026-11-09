import AppKit
import SwiftUI

/// Owns the objects every scene and window shares. Created once so the app
/// delegate, the menu bar menu and the AppKit windows all talk to the same
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
            Image(systemName: "computermouse")
                .accessibilityLabel("Citlla E510")
        }
    }
}
