import AppKit
import Foundation

/// One of the nine numbered callouts printed on the CITLLA PRO MAX E510's own
/// diagram. The numbers, titles and macOS notes here come straight from that
/// artwork so the app and the mouse's documentation describe the same layout.
struct MouseControl: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case button
        case wheel
        case tilt
        case indicator
    }

    /// Which of the two renders extracted from the diagram shows this control.
    enum Render: String, Hashable, Sendable {
        case top
        case side
    }

    let number: Int
    let title: String
    /// What the diagram says the control does, plus the macOS behaviour.
    let note: String
    let kind: Kind
    let render: Render
    /// Mouse-button numbers (1-based, as the event tap sees them) that this
    /// control is known to produce.
    let hidButtons: [Int]

    /// Where the manufacturer's callout arrow lands on the render, as a
    /// fraction of that render's width and height. Measured from the leader
    /// lines in `Design/citlla-diagram.png`, then mapped through the crop and
    /// trim in `Scripts/extract-assets.swift` (top view: 530x767 starting at
    /// diagram 225,588; side view: 320x753 starting at diagram 958,581).
    var badgePoint: CGPoint {
        switch number {
        case 1: CGPoint(x: 0.419, y: 0.113)   // left button, front-left of the top view
        case 2: CGPoint(x: 0.719, y: 0.098)   // right button, front-right of the top view
        case 3: CGPoint(x: 0.583, y: 0.194)   // scroll wheel, centre of the top view
        case 4: CGPoint(x: 0.555, y: 0.372)   // DPI button, behind the wheel
        case 5: CGPoint(x: 0.744, y: 0.436)   // side wheel, middle of the side view
        case 6: CGPoint(x: 0.816, y: 0.547)   // devices switch, below the side wheel
        case 7: CGPoint(x: 0.363, y: 0.214)   // LED strip, upper side view
        case 8: CGPoint(x: 0.594, y: 0.495)   // between the two thumb buttons
        case 9: CGPoint(x: 0.064, y: 0.459)   // bottom thumb button, left edge of the top view
        default: CGPoint(x: 0.5, y: 0.5)
        }
    }

    var id: Int { number }

    /// The LEDs on top of the mouse are not buttons; there is nothing to remap.
    var isRemappable: Bool { kind != .indicator }

    /// The keys the factory profile makes macOS receive, if this control sends
    /// a keystroke instead of a mouse button.
    var factoryShortcuts: [(keyCode: UInt16, modifiers: UInt)] {
        switch number {
        case 8: [
            (123, NSEvent.ModifierFlags.control.rawValue),          // ⌃← rear thumb button
            (124, NSEvent.ModifierFlags.control.rawValue)           // ⌃→ front thumb button
        ]
        case 6: [(48, NSEvent.ModifierFlags.command.rawValue)]      // ⌘Tab
        case 9: [(
            3,
            NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.command.rawValue
        )]                                                          // ⌃⌘F
        default: []
        }
    }
}

enum MouseMap {
    static let controls: [MouseControl] = [
        MouseControl(
            number: 1,
            title: "Left Button",
            note: "Primary click. Left native.",
            kind: .button,
            render: .top,
            hidButtons: [1]
        ),
        MouseControl(
            number: 2,
            title: "Right Button",
            note: "Secondary click. Left native.",
            kind: .button,
            render: .top,
            hidButtons: [2]
        ),
        MouseControl(
            number: 3,
            title: "Smart Flying Scroll Wheel",
            note: "Scrolls, and clicks as the middle button.",
            kind: .wheel,
            render: .top,
            hidButtons: [3]
        ),
        MouseControl(
            number: 4,
            title: "DPI Button",
            note: "Cycles DPI presets. Sends no keystroke, so the Mac may not see it.",
            kind: .button,
            render: .top,
            hidButtons: []
        ),
        MouseControl(
            number: 5,
            title: "Side Wheel",
            note: "Horizontal scroll — arrives as a wheel tilt.",
            kind: .tilt,
            render: .side,
            hidButtons: []
        ),
        MouseControl(
            number: 6,
            title: "Devices Switch Button",
            note: "Paired-device switcher. Factory profile sends ⌘Tab.",
            kind: .button,
            render: .side,
            hidButtons: []
        ),
        MouseControl(
            number: 7,
            title: "Devices Indicators",
            note: "2.4G, Bluetooth 1/2, DPI and low-power LEDs. Not a button.",
            kind: .indicator,
            render: .side,
            hidButtons: []
        ),
        MouseControl(
            number: 8,
            title: "Forward / Back Buttons",
            note: "Two thumb buttons. This mouse sends them as ⌃← and ⌃→ keystrokes.",
            kind: .button,
            render: .side,
            hidButtons: []
        ),
        MouseControl(
            number: 9,
            title: "Return to Desktop / Full Screen",
            note: "Bottom-right thumb button. Factory profile sends ⌃⌘F.",
            kind: .button,
            render: .top,
            hidButtons: []
        )
    ]

    static func control(number: Int) -> MouseControl? {
        controls.first { $0.number == number }
    }

    /// The callout a 1-based mouse button belongs to.
    static func control(forButton button: Int) -> MouseControl? {
        controls.first { $0.hidButtons.contains(button) }
    }

    /// The callout for a keyboard shortcut the mouse sends for us. Compared
    /// against the device-independent flags so Caps Lock and the like do not
    /// break the match.
    static func control(forKeyCode keyCode: UInt16, modifiers: UInt) -> MouseControl? {
        let flags = ShortcutBinding.masked(modifiers)
        return controls.first { control in
            control.factoryShortcuts.contains { factory in
                factory.keyCode == keyCode && ShortcutBinding.masked(factory.modifiers) == flags
            }
        }
    }

    /// The callout a stored shortcut binding belongs to, if the diagram names
    /// the control that sends it.
    static func control(forShortcut binding: ShortcutBinding) -> MouseControl? {
        guard binding.source == .keyboard else { return nil }
        return control(forKeyCode: binding.keyCode, modifiers: binding.modifiers)
    }

    /// Every control that is worth showing in a "press it now" list.
    static var remappableControls: [MouseControl] { controls.filter(\.isRemappable) }
}
