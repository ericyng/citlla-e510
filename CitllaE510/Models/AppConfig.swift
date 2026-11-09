import Foundation

struct AppConfig: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var bindings: [ButtonBinding] = ButtonBinding.defaults
    /// Controls the mouse sends as keystrokes rather than as mouse buttons.
    var shortcutBindings: [ShortcutBinding] = ShortcutBinding.defaults

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
    }

    init() {}

    // Be forgiving when loading configs written by older builds.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        bindings = try container.decodeIfPresent([ButtonBinding].self, forKey: .bindings) ?? ButtonBinding.defaults

        // A config written before a control was mapped has no row for it, so
        // merge in any defaults it is missing. Existing rows (and the actions
        // the user chose for them) are left alone.
        var shortcuts = try container.decodeIfPresent([ShortcutBinding].self, forKey: .shortcutBindings)
            ?? ShortcutBinding.defaults
        for fallback in ShortcutBinding.defaults where !shortcuts.contains(where: { $0.id == fallback.id }) {
            shortcuts.append(fallback)
        }
        shortcutBindings = shortcuts
    }
}
