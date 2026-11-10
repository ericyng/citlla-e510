import Foundation

/// One direction of the side wheel.
///
/// The side wheel is HID `AC Pan`, which macOS reports on the horizontal scroll
/// axis (axis 2). A positive delta is treated as a tilt to the right; that is
/// the raw direction macOS uses (`ButtonTester` has always labelled it the same
/// way) and keeping the mapping in one place makes a swap a one-line change if
/// the hardware ever turns out to send the opposite sign.
enum TiltDirection: String, CaseIterable, Identifiable, Sendable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Tilt left"
        case .right: "Tilt right"
        }
    }

    var symbolName: String {
        switch self {
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }

    /// The owner a sequence started by this tilt runs under, so pressing the
    /// same way again cancels the run in flight.
    var owner: MacroOwner { .other("tilt-\(rawValue)") }

    static func direction(forHorizontalDelta delta: Int64) -> TiltDirection? {
        if delta > 0 { return .right }
        if delta < 0 { return .left }
        return nil
    }
}

/// Scroll direction and side-wheel settings.
///
/// The defaults are the stock macOS behaviour: no inversion and no tilt
/// actions, so a config written before this existed keeps behaving exactly as
/// it did.
struct ScrollSettings: Codable, Equatable, Sendable {
    var invertVertical: Bool = false
    var invertHorizontal: Bool = false
    /// Actions for the side wheel. `.none` leaves the tilt as a plain
    /// horizontal scroll.
    var tiltLeft: MouseAction = MouseAction()
    var tiltRight: MouseAction = MouseAction()

    /// True when at least one direction has an action, so the tap knows to
    /// watch the horizontal axis at all.
    var hasTiltActions: Bool { tiltLeft.isBound || tiltRight.isBound }

    func action(for direction: TiltDirection) -> MouseAction {
        switch direction {
        case .left: tiltLeft
        case .right: tiltRight
        }
    }

    mutating func setAction(_ action: MouseAction, for direction: TiltDirection) {
        switch direction {
        case .left: tiltLeft = action
        case .right: tiltRight = action
        }
    }

    init() {}

    // Same forgiveness as `AppConfig` and `MouseAction`: a config written by a
    // build without one of these keys must load, not reset the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        invertVertical = try container.decodeIfPresent(Bool.self, forKey: .invertVertical) ?? false
        invertHorizontal = try container.decodeIfPresent(Bool.self, forKey: .invertHorizontal) ?? false
        tiltLeft = try container.decodeIfPresent(MouseAction.self, forKey: .tiltLeft) ?? MouseAction()
        tiltRight = try container.decodeIfPresent(MouseAction.self, forKey: .tiltRight) ?? MouseAction()
    }
}

struct AppConfig: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var bindings: [ButtonBinding] = ButtonBinding.defaults
    /// Controls the mouse sends as keystrokes rather than as mouse buttons.
    var shortcutBindings: [ShortcutBinding] = ShortcutBinding.defaults
    /// Scroll direction and side wheel. Independent of `bindings`.
    var scroll: ScrollSettings = ScrollSettings()

    func action(for button: Int) -> MouseAction? {
        bindings.first(where: { $0.button == button })?.action
    }

    mutating func setAction(_ action: MouseAction, for button: Int) {
        if let index = bindings.firstIndex(where: { $0.button == button }) {
            bindings[index].action = action
        } else {
            bindings.append(ButtonBinding(button: button, action: action))
        }
    }

    func shortcut(id: String) -> ShortcutBinding? {
        shortcutBindings.first { $0.id == id }
    }

    /// The binding for a keyboard event the mouse sent, if there is one.
    func action(forKeyboardKeyCode keyCode: UInt16, modifiers: UInt) -> (ShortcutBinding, MouseAction)? {
        guard let binding = shortcutBindings.first(where: {
            $0.matches(keyCode: keyCode, modifiers: modifiers)
        }) else { return nil }
        return (binding, binding.action)
    }

    /// The binding for a consumer key the mouse sent, if there is one.
    func action(forConsumerKey key: Int32) -> (ShortcutBinding, MouseAction)? {
        guard let binding = shortcutBindings.first(where: {
            $0.source == .consumer && $0.consumerKey == key
        }) else { return nil }
        return (binding, binding.action)
    }

    mutating func setAction(_ action: MouseAction, forShortcut id: String) {
        guard let index = shortcutBindings.firstIndex(where: { $0.id == id }) else { return }
        shortcutBindings[index].action = action
    }

    /// Adds a keyboard trigger the mouse sent, so it can be bound later. Returns
    /// the id of the (possibly existing) trigger.
    @discardableResult
    mutating func learnKeyboardShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let candidate = ShortcutBinding(keyCode: keyCode, modifiers: modifiers)
        if let existing = shortcutBindings.first(where: { $0.id == candidate.id }) {
            return existing.id
        }
        shortcutBindings.append(candidate)
        return candidate.id
    }

    /// Adds a consumer-key trigger the mouse sent. Returns the id of the trigger.
    @discardableResult
    mutating func learnConsumerKey(_ key: Int32) -> String {
        let candidate = ShortcutBinding(source: .consumer, consumerKey: key)
        if let existing = shortcutBindings.first(where: { $0.id == candidate.id }) {
            return existing.id
        }
        shortcutBindings.append(candidate)
        return candidate.id
    }

    mutating func resetToDefaults() {
        bindings = ButtonBinding.defaults
        shortcutBindings = ShortcutBinding.defaults
        // Scrolling is deliberately untouched: the reset lives on the Buttons
        // page and says it resets buttons. The Scrolling page has its own
        // switches, and turning those off is the way back to stock scrolling.
    }

    init() {}

    // Be forgiving when loading configs written by older builds.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true

        // Older builds offered rows for buttons 4-8, which this mouse never
        // sends. Drop those rows, then merge in any reported button the config
        // is missing, so the Buttons tab always lists buttons 1-3 in order.
        let stored = try container.decodeIfPresent([ButtonBinding].self, forKey: .bindings)
            ?? ButtonBinding.defaults
        var buttons = stored.filter { !ButtonBinding.retiredButtons.contains($0.button) }
        for fallback in ButtonBinding.defaults where !buttons.contains(where: { $0.button == fallback.button }) {
            buttons.append(fallback)
        }
        bindings = buttons.sorted { $0.button < $1.button }

        // A config written before a control was mapped has no row for it, so
        // merge in any defaults it is missing. Existing rows (and the actions
        // the user chose for them) are left alone.
        var shortcuts = try container.decodeIfPresent([ShortcutBinding].self, forKey: .shortcutBindings)
            ?? ShortcutBinding.defaults
        for fallback in ShortcutBinding.defaults where !shortcuts.contains(where: { $0.id == fallback.id }) {
            shortcuts.append(fallback)
        }
        shortcutBindings = shortcuts

        // Configs written before the Scrolling section existed have no `scroll`
        // key, and must load with stock scrolling rather than fail and reset
        // every binding.
        scroll = try container.decodeIfPresent(ScrollSettings.self, forKey: .scroll) ?? ScrollSettings()
    }
}
