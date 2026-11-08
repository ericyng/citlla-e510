import AppKit
import Foundation

/// The kind of thing a mouse button should do.
enum ActionKind: String, CaseIterable, Codable, Identifiable {
    case none
    case system
    case keyboardShortcut
    case mouseClick
    case openApp
    case openURL
    case shellCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Do Nothing"
        case .system: "System Action"
        case .keyboardShortcut: "Keyboard Shortcut"
        case .mouseClick: "Mouse Click"
        case .openApp: "Open App"
        case .openURL: "Open URL"
        case .shellCommand: "Run Shell Command"
        }
    }

    var symbolName: String {
        switch self {
        case .none: "nosign"
        case .system: "gearshape.2"
        case .keyboardShortcut: "keyboard"
        case .mouseClick: "computermouse"
        case .openApp: "app.badge"
        case .openURL: "link"
        case .shellCommand: "terminal"
        }
    }
}

/// Built-in macOS actions that don't need a user-recorded shortcut.
enum SystemAction: String, CaseIterable, Codable, Identifiable {
    case back
    case forward
    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case spotlight
    case screenshot
    case lockScreen
    case sleepDisplay
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case nextTrack
    case previousTrack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: "Back"
        case .forward: "Forward"
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .launchpad: "Launchpad"
        case .spotlight: "Spotlight"
        case .screenshot: "Screenshot"
        case .lockScreen: "Lock Screen"
        case .sleepDisplay: "Sleep Display"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        }
    }

    var symbolName: String {
        switch self {
        case .back: "chevron.backward"
        case .forward: "chevron.forward"
        case .missionControl: "rectangle.3.group"
        case .appExpose: "rectangle.on.rectangle"
        case .showDesktop: "desktopcomputer"
        case .launchpad: "square.grid.3x3"
        case .spotlight: "magnifyingglass"
        case .screenshot: "camera.viewfinder"
        case .lockScreen: "lock"
        case .sleepDisplay: "moon.zzz"
        case .volumeUp: "speaker.wave.3"
        case .volumeDown: "speaker.wave.1"
        case .mute: "speaker.slash"
        case .playPause: "playpause"
        case .nextTrack: "forward.end"
        case .previousTrack: "backward.end"
        }
    }
}

enum MouseClickKind: Int, CaseIterable, Codable, Identifiable {
    case left = 0
    case right = 1
    case middle = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .left: "Left Click"
        case .right: "Right Click"
        case .middle: "Middle Click"
        }
    }
}

/// A serializable description of one button action.
///
/// This is deliberately a flat struct rather than an enum with associated
/// values: it keeps the on-disk JSON readable and makes the editor in
/// `ActionEditorSheet` straightforward.
struct MouseAction: Codable, Equatable, Sendable {
    var kind: ActionKind = .none
    var system: SystemAction = .missionControl
    var keyCode: UInt16 = 0
    var modifiers: UInt = 0
    var hasShortcut: Bool = false
    var click: MouseClickKind = .middle
    var text: String = ""

    static let none = MouseAction()

    var isBound: Bool { kind != .none }

    var symbolName: String {
        switch kind {
        case .none: "nosign"
        case .system: system.symbolName
        case .keyboardShortcut: "keyboard"
        case .mouseClick: "computermouse"
        case .openApp: "app.badge"
        case .openURL: "link"
        case .shellCommand: "terminal"
        }
    }

    var summary: String {
        switch kind {
        case .none:
            return "Pass through"
        case .system:
            return system.title
        case .keyboardShortcut:
            guard hasShortcut else { return "No shortcut recorded" }
            return KeyCodeMap.describe(keyCode: keyCode, modifiers: modifiers)
        case .mouseClick:
            return click.title
        case .openApp:
            guard !text.isEmpty else { return "No app selected" }
            return URL(fileURLWithPath: text).lastPathComponent
        case .openURL:
            return text.isEmpty ? "No URL set" : text
        case .shellCommand:
            return text.isEmpty ? "No command set" : text
        }
    }
}
