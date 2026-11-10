import AppKit
import SwiftUI

/// Preferences that live outside `AppConfig` because they are about the app's
/// presence, not about how the mouse behaves.
enum AppPreferences {
    /// Off (the default): the Dock icon appears only while a window is open.
    /// On: the app stays in the Dock and in ⌘-Tab all the time.
    static let keepInDock = "keepInDock"
}

/// The app's single window scene. Used with SwiftUI's `openWindow`.
enum AppWindowID {
    static let main = "main"
}

/// The two panes of the Advanced section. The tester and diagnostics used to be
/// separate windows; they are panes of the main window now.
enum AdvancedPane: String, CaseIterable, Identifiable, Hashable {
    case tester
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tester: "Button Tester"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbolName: String {
        switch self {
        case .tester: "hand.tap"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

/// The selection and open state of the main window. Owned by `WindowManager`
/// and handed to the window's views as an environment object, so anything in
/// the app (menu bar, AppDelegate, a command) can send the window to a section.
@MainActor
final class MainWindowState: ObservableObject {
    @Published var selection: MainSection = .overview
    @Published var advancedPane: AdvancedPane = .tester
    @Published var isOpen = false
}

/// Owns the app's windows and its activation policy.
///
/// The app is a menu bar utility (`LSUIElement`), so it starts with no Dock icon
/// and no ⌘-Tab entry. Opening the main window switches to `.regular` so it gets
/// a real Dock icon and app menu; closing the last window goes back to
/// `.accessory`, unless *Keep in Dock* is on. Remapping is untouched by any of
/// this: the event tap runs on the main run loop and does not care about the
/// activation policy.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var config: ConfigStore?
    private var eventTap: EventTapService?
    private(set) var tagger: MouseKeyTagger?
    private var loginItem: LoginItemManager?

    /// The one main window's selection, shared with its SwiftUI views.
    let state = MainWindowState()

    /// The tester is kept here so the Tester pane and the menu bar item share
    /// one instance (and one listen-only tap).
    private(set) var tester: ButtonTester?

    /// Captured from the menu bar label's environment. Until SwiftUI hands it
    /// over, an open request is queued rather than dropped.
    private var openWindowAction: OpenWindowAction?
    private var wantsMainWindow = false

    private init() {}

    func configure(
        config: ConfigStore,
        eventTap: EventTapService,
        tagger: MouseKeyTagger,
        loginItem: LoginItemManager
    ) {
        self.config = config
        self.eventTap = eventTap
        self.tagger = tagger
        self.loginItem = loginItem
        tester = ButtonTester(config: config, tagger: tagger)
    }

    // MARK: - Opening

    /// Called from the menu bar label once SwiftUI has an `openWindow` action.
    func register(openWindow: OpenWindowAction) {
        openWindowAction = openWindow
        if wantsMainWindow {
            wantsMainWindow = false
            presentMainWindow()
        }
    }

    /// Opens the main window on `section`, switching to `.regular` first so the
    /// window has a Dock icon and an app menu for as long as it is open.
    func showMain(section: MainSection) {
        state.selection = section
        wantsMainWindow = true
        presentMainWindow()
    }

    /// The old settings entry point, kept for call sites that still pass a
    /// `SettingsTab` (the AppDelegate and the snapshot tool). Each tab maps onto
    /// the main window section that now hosts it.
    func showSettings(tab: SettingsTab = .mouse) {
        showMain(section: tab.mainSection)
    }

    func showTester() {
        state.advancedPane = .tester
        showMain(section: .advanced)
        tester?.start()
    }

    func showDiagnostics() {
        state.advancedPane = .diagnostics
        showMain(section: .advanced)
    }

    private func presentMainWindow() {
        guard let openWindowAction else { return }
        wantsMainWindow = false
        // A `Window` scene in an accessory app is created but not shown. The
        // policy switch has to come first, otherwise the window has no Dock
        // icon and no app menu.
        _ = NSApp.setActivationPolicy(.regular)
        openWindowAction(id: AppWindowID.main)
        NSApp.activate()
    }

    // MARK: - Presence

    /// Called by the main window when it appears and disappears.
    func mainWindowOpened() {
        state.isOpen = true
        applyActivationPolicy()
    }

    func mainWindowClosed() {
        state.isOpen = false
        applyActivationPolicy()
    }

    /// Applies the policy the current state asks for: `.regular` while the
    /// window is open or *Keep in Dock* is on, `.accessory` otherwise.
    func applyActivationPolicy() {
        let keepInDock = UserDefaults.standard.bool(forKey: AppPreferences.keepInDock)
        let wantsDockIcon = state.isOpen || keepInDock
        let policy: NSApplication.ActivationPolicy = wantsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        _ = NSApp.setActivationPolicy(policy)
    }

    func setKeepInDock(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: AppPreferences.keepInDock)
        applyActivationPolicy()
    }

    /// Restores the window when the Dock icon is clicked with no window open.
    func reopen() {
        showMain(section: state.selection)
    }
}

extension SettingsTab {
    /// The main window section that hosts this old settings tab.
    var mainSection: MainSection {
        switch self {
        case .mouse, .buttons: .buttons
        case .permissions: .permissions
        case .about: .about
        }
    }
}
