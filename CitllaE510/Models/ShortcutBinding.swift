import AppKit
import Foundation

/// A keyboard or consumer-control key that the mouse sends *instead of* a mouse
/// button.
///
/// The CITLLA PRO MAX E510 does not report its extra buttons as mouse buttons.
/// The receiver also presents a keyboard interface, and several controls send
/// real key presses:
///
///   - the two thumb buttons (diagram callout 8) send `⌃←` and `⌃→`
///   - the ninth control (diagram callout 9) sends `⌃⌘F`
///   - another control sends a consumer key (`NX_KEYTYPE_SOUND_UP`)
///
/// A session event tap cannot tell which device a key came from, so the app only
/// acts on these when its HID listener has just seen the mouse send that key
/// (see `MouseKeyTagger`).
struct ShortcutBinding: Codable, Identifiable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        /// A normal keyboard event: a virtual key code plus modifiers.
        case keyboard
        /// A media / system key, which arrives as `NX_SYSDEFINED`.
        case consumer
    }

    var source: Source = .keyboard
    /// CG virtual key code for `.keyboard` triggers.
    var keyCode: UInt16 = 0
    /// `NSEvent.ModifierFlags` (only ⌃⌥⇧⌘ are significant) for `.keyboard` triggers.
    var modifiers: UInt = 0
    /// `NX_KEYTYPE_*` for `.consumer` triggers.
    var consumerKey: Int32 = 0
    var action: MouseAction = .none

    var id: String {
        switch source {
        case .keyboard: "key-\(keyCode)-\(Self.masked(modifiers))"
        case .consumer: "consumer-\(consumerKey)"
        }
    }

    var name: String {
        switch source {
        case .keyboard: KeyCodeMap.describe(keyCode: keyCode, modifiers: modifiers)
        case .consumer: Self.consumerName(consumerKey)
        }
    }

    var subtitle: String {
        switch source {
        case .keyboard: "Sent by the mouse as a keystroke"
        case .consumer: "Sent by the mouse as a media key"
        }
    }

    var isBound: Bool { action.isBound }

    // MARK: - Matching

    /// The modifier flags an event can carry that matter for matching.
    static func masked(_ flags: UInt) -> UInt {
        let interesting: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        return flags & interesting.rawValue
    }

    static func masked(_ flags: CGEventFlags) -> UInt {
        var result: UInt = 0
        if flags.contains(.maskControl) { result |= NSEvent.ModifierFlags.control.rawValue }
        if flags.contains(.maskAlternate) { result |= NSEvent.ModifierFlags.option.rawValue }
        if flags.contains(.maskShift) { result |= NSEvent.ModifierFlags.shift.rawValue }
        if flags.contains(.maskCommand) { result |= NSEvent.ModifierFlags.command.rawValue }
        return result
    }

    /// True when this binding describes the given keyboard event.
    func matches(keyCode: UInt16, modifiers: UInt) -> Bool {
        source == .keyboard
            && self.keyCode == keyCode
            && Self.masked(self.modifiers) == Self.masked(modifiers)
    }

    // MARK: - Defaults

    /// The extra controls this mouse sends as keystrokes.
    ///
    /// The ninth control starts unbound so the factory `⌃⌘F` keeps working
    /// until the user picks an action for it; the row still appears in Settings
    /// and the tester so it can be remapped like any other control.
    static let defaults: [ShortcutBinding] = [
        ShortcutBinding(
            keyCode: 123,                                   // ⌃← — rear thumb button
            modifiers: NSEvent.ModifierFlags.control.rawValue,
            action: MouseAction(kind: .system, system: .back)
        ),
        ShortcutBinding(
            keyCode: 124,                                   // ⌃→ — front thumb button
            modifiers: NSEvent.ModifierFlags.control.rawValue,
            action: MouseAction(kind: .system, system: .forward)
        ),
        ShortcutBinding(
            keyCode: 3,                                     // ⌃⌘F — callout 9
            modifiers: NSEvent.ModifierFlags.control.rawValue
                | NSEvent.ModifierFlags.command.rawValue,
            action: .none
        )
    ]

    /// `NX_KEYTYPE_*` names, for the tester and the settings list.
    static func consumerName(_ key: Int32) -> String {
        switch key {
        case 0: "Volume Up"
        case 1: "Volume Down"
        case 2: "Brightness Up"
        case 3: "Brightness Down"
        case 4: "Caps Lock"
        case 5: "Help"
        case 6: "Power"
        case 7: "Mute"
        case 8: "Up Arrow"
        case 9: "Down Arrow"
        case 10: "Num Lock"
        case 11: "Contrast Up"
        case 12: "Contrast Down"
        case 13: "Launch Panel"
        case 14: "Eject"
        case 15: "Video Mirror"
        case 16: "Play / Pause"
        case 17: "Next Track"
        case 18: "Previous Track"
        case 19: "Fast Forward"
        case 20: "Rewind"
        default: "Media key \(key)"
        }
    }
}
