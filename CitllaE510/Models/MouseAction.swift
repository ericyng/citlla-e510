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
    case sequence

    var id: String { rawValue }

    /// Kinds the action editor offers. `.sequence` is hidden until the step
    /// editor lands, so the picker never offers an option with no UI behind it.
    /// The kind still exists now so configs, the runner and the tests can be
    /// written against a frozen type.
    static var editableCases: [ActionKind] { allCases.filter { $0 != .sequence } }

    /// Kinds a sequence step may hold. A step cannot itself be a sequence;
    /// nesting is flattened when a config loads.
    static var stepCases: [ActionKind] { allCases.filter { $0 != .sequence } }

    var title: String {
        switch self {
        case .none: "Do Nothing"
        case .system: "System Action"
        case .keyboardShortcut: "Keyboard Shortcut"
        case .mouseClick: "Mouse Click"
        case .openApp: "Open App"
        case .openURL: "Open URL"
        case .shellCommand: "Run Shell Command"
        case .sequence: "Sequence"
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
        case .sequence: "list.number"
        }
    }
}

/// The hard limits a sequence is held to.
///
/// They exist because the runner posts real events: a long sequence is a long
/// time between the press and the last event, and a stuck modifier is a system
/// wide problem. The editor and the decoder both clamp to these values.
enum SequenceLimits {
    static let maxSteps = 8
    static let maxStepDelayMilliseconds = 500
    static let maxTotalMilliseconds = 3000
    /// A short gap is enough for the target app to take focus after a click or
    /// an app launch, without the user noticing the sequence.
    static let defaultStepDelayMilliseconds = 40
    /// Opening an app needs longer before keys land in its window.
    static let defaultDelayAfterOpenAppMilliseconds = 150
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

    /// Why a remapped button cannot drive this action, when it cannot.
    ///
    /// These two are symbolic hotkeys: WindowServer matches them against real
    /// HID key presses and ignores synthetic events from every source, so
    /// there is no way to fire them from a mouse button. The rest of the system
    /// actions either go through the Dock (Mission Control and friends) or are
    /// plain key/media events, which do work.
    var unavailableNote: String? {
        switch self {
        case .spotlight:
            "macOS only opens Spotlight for a real ⌘Space key press, so a remapped button cannot trigger it. Pick another action, or bind the button to a keyboard shortcut."
        case .lockScreen:
            "macOS only locks the screen for a real ⌃⌘Q key press, so a remapped button cannot trigger it. Use the Apple menu › Lock Screen, or pick another action."
        default:
            nil
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

/// One step of a sequence.
///
/// Deliberately flat like `MouseAction`, and for the same reason: readable JSON
/// and one set of controls can drive both. `kind` can be anything except
/// `.sequence`; nested sequences are flattened when a config loads.
struct ActionStep: Codable, Equatable, Sendable {
    var kind: ActionKind = .none
    var system: SystemAction = .missionControl
    var keyCode: UInt16 = 0
    var modifiers: UInt = 0
    var hasShortcut: Bool = false
    var click: MouseClickKind = .middle
    var clickModifiers: UInt = 0
    var text: String = ""
    /// How long to wait *before* this step fires. Clamped to
    /// `SequenceLimits.maxStepDelayMilliseconds`.
    var delayMilliseconds: Int = 0

    var clampedDelay: Int {
        min(max(delayMilliseconds, 0), SequenceLimits.maxStepDelayMilliseconds)
    }

    /// The step as a standalone action, so the executor and `summary` can be
    /// reused instead of duplicated.
    var asAction: MouseAction {
        MouseAction(
            kind: kind,
            system: system,
            keyCode: keyCode,
            modifiers: modifiers,
            hasShortcut: hasShortcut,
            click: click,
            clickModifiers: clickModifiers,
            text: text
        )
    }

    var summary: String { asAction.summary }
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
    /// Modifiers held for a `.mouseClick` (⌘-click, ⌥-click, …). An
    /// `NSEvent.ModifierFlags` raw value, like `modifiers`.
    var clickModifiers: UInt = 0
    var text: String = ""
    /// Used when `kind == .sequence`.
    var steps: [ActionStep] = []

    static let none = MouseAction()

    var isBound: Bool {
        switch kind {
        case .none: false
        case .sequence: !steps.isEmpty
        default: true
        }
    }

    var symbolName: String {
        switch kind {
        case .none: "nosign"
        case .system: system.symbolName
        case .keyboardShortcut: "keyboard"
        case .mouseClick: "computermouse"
        case .openApp: "app.badge"
        case .openURL: "link"
        case .shellCommand: "terminal"
        case .sequence: "list.number"
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
            return Self.describe(click: click, modifiers: clickModifiers)
        case .openApp:
            guard !text.isEmpty else { return "No app selected" }
            return URL(fileURLWithPath: text).lastPathComponent
        case .openURL:
            return text.isEmpty ? "No URL set" : text
        case .shellCommand:
            return text.isEmpty ? "No command set" : text
        case .sequence:
            let parts = steps.map(\.summary)
            guard !parts.isEmpty else { return "No steps" }
            if parts.count <= 3 { return parts.joined(separator: " → ") }
            return parts.prefix(2).joined(separator: " → ") + " → … (\(parts.count) steps)"
        }
    }

    /// The action as a single step, so the executor has one input type.
    var asStep: ActionStep {
        ActionStep(
            kind: kind,
            system: system,
            keyCode: keyCode,
            modifiers: modifiers,
            hasShortcut: hasShortcut,
            click: click,
            clickModifiers: clickModifiers,
            text: text
        )
    }

    /// The steps the runner should actually fire for this action.
    ///
    /// Only a `.sequence` has steps. Asking any other kind returns nothing, so a
    /// stale step list left over from a previous edit can never run.
    func normalizedSequence() -> [ActionStep] {
        kind == .sequence ? steps.normalized() : []
    }

    /// "Left Click", "⌘ Left Click", "⌥ Right Click", … — the mouse legend and
    /// the editor share this so a chord reads the same everywhere.
    static func describe(click: MouseClickKind, modifiers: UInt) -> String {
        let prefix = KeyCodeMap.modifierSymbols(modifiers)
        return prefix.isEmpty ? click.title : "\(prefix) \(click.title)"
    }

    // Be forgiving when loading configs written by older builds. Without this,
    // the synthesized decoder would reject every file saved before
    // `clickModifiers` and `steps` existed, and `ConfigStore` would silently
    // fall back to defaults and drop the user's bindings.
    init() {}

    init(
        kind: ActionKind = .none,
        system: SystemAction = .missionControl,
        keyCode: UInt16 = 0,
        modifiers: UInt = 0,
        hasShortcut: Bool = false,
        click: MouseClickKind = .middle,
        clickModifiers: UInt = 0,
        text: String = "",
        steps: [ActionStep] = []
    ) {
        self.kind = kind
        self.system = system
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.hasShortcut = hasShortcut
        self.click = click
        self.clickModifiers = clickModifiers
        self.text = text
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(ActionKind.self, forKey: .kind) ?? .none
        system = try container.decodeIfPresent(SystemAction.self, forKey: .system) ?? .missionControl
        keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode) ?? 0
        modifiers = try container.decodeIfPresent(UInt.self, forKey: .modifiers) ?? 0
        hasShortcut = try container.decodeIfPresent(Bool.self, forKey: .hasShortcut) ?? false
        click = try container.decodeIfPresent(MouseClickKind.self, forKey: .click) ?? .middle
        clickModifiers = try container.decodeIfPresent(UInt.self, forKey: .clickModifiers) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        steps = try container.decodeIfPresent([ActionStep].self, forKey: .steps) ?? []
    }
}

extension Array where Element == ActionStep {
    /// A copy the runner can trust.
    ///
    /// Steps come from `config.json`, which is plain JSON and can be hand-edited,
    /// so the runner cannot rely on the editor having enforced `SequenceLimits`.
    /// This clamps each delay, drops steps that do nothing or that try to nest a
    /// sequence (the editor cannot create either), and keeps only the first
    /// `maxSteps` executable steps in order. Invalid entries are dropped rather
    /// than made fatal: a broken macro should cost one step, not the config.
    func normalized() -> [ActionStep] {
        var result: [ActionStep] = []
        result.reserveCapacity(SequenceLimits.maxSteps)
        for var step in self where step.kind != .none && step.kind != .sequence {
            guard result.count < SequenceLimits.maxSteps else { break }
            step.delayMilliseconds = step.clampedDelay
            result.append(step)
        }
        return result
    }
}
