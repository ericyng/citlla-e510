import AppKit
import Foundation

// MARK: - Chord modifiers

/// The four modifiers a click can hold, and the small amount of bit
/// manipulation the chord row needs.
///
/// `MouseAction.clickModifiers` is an `NSEvent.ModifierFlags` raw value, which
/// uses the same bit values as `CGEventFlags`; the executor presses the
/// modifiers for real, so ⌘-click reaches an app as a genuine chord rather than
/// just a stamped flag.
enum ChordModifier: String, CaseIterable, Identifiable, Sendable {
    case control
    case option
    case shift
    case command

    var id: String { rawValue }

    var flag: UInt {
        switch self {
        case .control: NSEvent.ModifierFlags.control.rawValue
        case .option: NSEvent.ModifierFlags.option.rawValue
        case .shift: NSEvent.ModifierFlags.shift.rawValue
        case .command: NSEvent.ModifierFlags.command.rawValue
        }
    }

    /// The glyph macOS writes for this modifier.
    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var title: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        }
    }

    static func isOn(_ modifier: ChordModifier, in mask: UInt) -> Bool {
        mask & modifier.flag != 0
    }

    /// The mask with `modifier` added or removed. Kept here, rather than in the
    /// view, so the toggle has a test without a running UI.
    static func setting(_ modifier: ChordModifier, on: Bool, in mask: UInt) -> UInt {
        on ? mask | modifier.flag : mask & ~modifier.flag
    }

    static func modifiers(in mask: UInt) -> Set<ChordModifier> {
        Set(allCases.filter { isOn($0, in: mask) })
    }

    static func mask(of modifiers: Set<ChordModifier>) -> UInt {
        modifiers.reduce(0) { $0 | $1.flag }
    }
}

// MARK: - Step list editing

/// Add, duplicate, delete and reorder for a sequence's steps.
///
/// `ActionStep` has no identity of its own (it is a frozen Codable shape), so
/// these are plain array edits. They live here rather than in the view so the
/// caps and the default delays can be tested without SwiftUI.
extension Array where Element == ActionStep {
    /// A sequence can hold at most `SequenceLimits.maxSteps` steps. The add
    /// button disables at the cap; this is the model half of the same rule.
    var canAddStep: Bool { count < SequenceLimits.maxSteps }

    /// The wait before the next step: 40 ms normally, 150 ms after an Open App
    /// step so the app has taken focus, and none before the first step.
    static func defaultDelay(after previous: ActionStep?) -> Int {
        guard let previous else { return 0 }
        return previous.kind == .openApp
            ? SequenceLimits.defaultDelayAfterOpenAppMilliseconds
            : SequenceLimits.defaultStepDelayMilliseconds
    }

    /// The step a fresh row starts as. A keyboard shortcut is the most common
    /// first move in a macro, and the recorder explains itself.
    static func defaultStep(after previous: ActionStep?) -> ActionStep {
        ActionStep(
            kind: .keyboardShortcut,
            delayMilliseconds: defaultDelay(after: previous)
        )
    }

    /// Appends a step, unless the sequence is already at the cap. Returns
    /// whether it was added.
    @discardableResult
    mutating func addStep() -> Bool {
        guard canAddStep else { return false }
        append(Self.defaultStep(after: last))
        return true
    }

    /// Copies the step at `index` and puts the copy directly after it.
    @discardableResult
    mutating func duplicateStep(at index: Int) -> Bool {
        guard indices.contains(index), canAddStep else { return false }
        insert(self[index], at: index + 1)
        return true
    }

    @discardableResult
    mutating func deleteStep(at index: Int) -> Bool {
        guard indices.contains(index) else { return false }
        remove(at: index)
        return true
    }

    /// Moves the step at `source` to `destination`, the model half of both the
    /// drag handle and the up/down buttons.
    @discardableResult
    mutating func moveStep(from source: Int, to destination: Int) -> Bool {
        guard indices.contains(source),
              destination >= 0,
              destination < count,
              source != destination else { return false }
        let step = remove(at: source)
        insert(step, at: destination)
        return true
    }
}

// MARK: - Preview text

/// The editor's live preview of a sequence.
///
/// `MouseAction.summary` is the compact form the mouse map and the buttons rows
/// use ("⌘C → ⌘V"); it deliberately omits waits so a legend row stays one line.
/// The editor shows this longer form instead: each step's wait is printed just
/// before the step it delays, so "Copy → 100 ms → Paste" reads in firing order.
enum SequencePreview {
    static func text(for steps: [ActionStep]) -> String {
        let parts = steps.prefix(SequenceLimits.maxSteps).flatMap { step -> [String] in
            var parts: [String] = []
            if step.clampedDelay > 0 {
                parts.append("\(step.clampedDelay) ms")
            }
            parts.append(step.summary)
            return parts
        }
        return parts.isEmpty ? "No steps" : parts.joined(separator: " → ")
    }

    /// The total waiting a run would do. The runner stops at
    /// `SequenceLimits.maxTotalMilliseconds`; the editor warns when the list
    /// goes over it instead of silently dropping steps at run time.
    static func totalDelay(of steps: [ActionStep]) -> Int {
        steps.prefix(SequenceLimits.maxSteps).reduce(0) { $0 + $1.clampedDelay }
    }
}

// MARK: - Presets

/// A ready-made action that fills the editor's draft.
struct ActionPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let symbolName: String
    let make: @Sendable () -> MouseAction
}

private enum PresetKey {
    static let command = NSEvent.ModifierFlags.command.rawValue
    static let shiftCommand = NSEvent.ModifierFlags([.shift, .command]).rawValue
    static let controlShiftCommand = NSEvent.ModifierFlags([.control, .shift, .command]).rawValue

    static let c: UInt16 = 8
    static let v: UInt16 = 9
    static let t: UInt16 = 17
    static let n: UInt16 = 45
    static let four: UInt16 = 21
}

extension ActionPreset {
    static var all: [ActionPreset] {
        [
            ActionPreset(
                id: "copy-paste",
                name: "Copy → Paste",
                detail: "⌘C, wait 100 ms, then ⌘V. The wait lets the app put the selection on the pasteboard first.",
                symbolName: "doc.on.doc"
            ) {
                MouseAction(kind: .sequence, steps: [
                    ActionStep(kind: .keyboardShortcut, keyCode: PresetKey.c, modifiers: PresetKey.command, hasShortcut: true),
                    ActionStep(
                        kind: .keyboardShortcut,
                        keyCode: PresetKey.v,
                        modifiers: PresetKey.command,
                        hasShortcut: true,
                        delayMilliseconds: 100
                    )
                ])
            },
            ActionPreset(
                id: "screenshot-area",
                name: "Screenshot Area to Clipboard",
                detail: "Sends ⌃⇧⌘4, which captures a selected area straight to the clipboard. The executor presses the modifiers for real, so WindowServer accepts the hotkey.",
                symbolName: "camera.viewfinder"
            ) {
                MouseAction(
                    kind: .keyboardShortcut,
                    keyCode: PresetKey.four,
                    modifiers: PresetKey.controlShiftCommand,
                    hasShortcut: true
                )
            },
            ActionPreset(
                id: "safari-new-tab",
                name: "Safari: New Tab",
                detail: "Activates Safari, waits 150 ms for its window, then ⌘T. ⌘T is used rather than ⌘L then Return because it works from any Safari window state, with no address bar focus to depend on.",
                symbolName: "safari"
            ) {
                MouseAction(kind: .sequence, steps: [
                    ActionStep(kind: .openApp, text: "/Applications/Safari.app"),
                    ActionStep(
                        kind: .keyboardShortcut,
                        keyCode: PresetKey.t,
                        modifiers: PresetKey.command,
                        hasShortcut: true,
                        delayMilliseconds: SequenceLimits.defaultDelayAfterOpenAppMilliseconds
                    )
                ])
            },
            ActionPreset(
                id: "finder-new-folder",
                name: "Finder: New Folder",
                detail: "Sends ⇧⌘N, Finder's New Folder shortcut.",
                symbolName: "folder.badge.plus"
            ) {
                MouseAction(
                    kind: .keyboardShortcut,
                    keyCode: PresetKey.n,
                    modifiers: PresetKey.shiftCommand,
                    hasShortcut: true
                )
            },
            ActionPreset(
                id: "open-app-new-window",
                name: "Open App → New Window",
                detail: "Opens TextEdit, waits 150 ms, then ⌘N for a new document. Choose a different app in the step before saving.",
                symbolName: "app.badge"
            ) {
                MouseAction(kind: .sequence, steps: [
                    ActionStep(kind: .openApp, text: "/System/Applications/TextEdit.app"),
                    ActionStep(
                        kind: .keyboardShortcut,
                        keyCode: PresetKey.n,
                        modifiers: PresetKey.command,
                        hasShortcut: true,
                        delayMilliseconds: SequenceLimits.defaultDelayAfterOpenAppMilliseconds
                    )
                ])
            },
            ActionPreset(
                id: "command-click",
                name: "⌘-Click",
                detail: "A real command-click at the pointer: ⌘ is held down around the click, so links open in a new tab.",
                symbolName: "cursorarrow.click"
            ) {
                MouseAction(kind: .mouseClick, click: .left, clickModifiers: PresetKey.command)
            }
        ]
    }
}
