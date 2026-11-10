import Foundation

/// A per-app override of the global button and mouse-key map.
///
/// A profile is identified by bundle identifier, which is what
/// `NSWorkspace.didActivateApplicationNotification` reports. The global mapping
/// stays the default: a button or key the profile does not mention falls back to
/// it, and a disabled profile is ignored entirely.
///
/// The stored shape is frozen by the contract commit. Only lookup helpers live
/// here; resolution itself is in `AppConfig`, where the global map also lives.
struct AppProfile: Codable, Identifiable, Equatable, Sendable {
    /// Bundle identifier, e.g. `com.google.Chrome`.
    var id: String
    /// Display name captured when the rule was added; the running app may
    /// change it, so this is a hint, not a lookup key.
    var name: String
    var enabled: Bool = true
    /// Overrides by `ButtonBinding.button` (1-based).
    var buttonActions: [Int: MouseAction] = [:]
    /// Overrides by `ShortcutBinding.id`.
    var shortcutActions: [String: MouseAction] = [:]

    init(
        id: String,
        name: String,
        enabled: Bool = true,
        buttonActions: [Int: MouseAction] = [:],
        shortcutActions: [String: MouseAction] = [:]
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.buttonActions = buttonActions
        self.shortcutActions = shortcutActions
    }

    // MARK: - Overrides

    /// The override for a button, or `nil` when the profile follows the global
    /// map. An entry that is stored but unbound is treated as no override, so a
    /// half-edited profile can never turn a working global action off.
    func buttonAction(for button: Int) -> MouseAction? {
        guard let action = buttonActions[button], action.isBound else { return nil }
        return action
    }

    /// The override for a keyboard or consumer control, by `ShortcutBinding.id`.
    func shortcutAction(for id: String) -> MouseAction? {
        guard let action = shortcutActions[id], action.isBound else { return nil }
        return action
    }

    /// Number of controls this profile really overrides. Unbound entries are
    /// not counted, so the row's summary matches what the tap does.
    var overrideCount: Int {
        buttonActions.values.filter(\.isBound).count
            + shortcutActions.values.filter(\.isBound).count
    }

    /// Stores an override. `nil` (or an unbound action) removes it and puts the
    /// control back on the global map.
    mutating func setButtonAction(_ action: MouseAction?, for button: Int) {
        if let action, action.isBound {
            buttonActions[button] = action
        } else {
            buttonActions[button] = nil
        }
    }

    /// Stores an override, by `ShortcutBinding.id`. `nil` (or an unbound
    /// action) removes it.
    mutating func setShortcutAction(_ action: MouseAction?, for id: String) {
        if let action, action.isBound {
            shortcutActions[id] = action
        } else {
            shortcutActions[id] = nil
        }
    }

    // Forgiving decode, like `MouseAction` and `AppConfig`: a profile written
    // by a build with a missing key (or hand-edited JSON) must load rather than
    // fail the whole config and silently reset every binding.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        buttonActions = try container.decodeIfPresent([Int: MouseAction].self, forKey: .buttonActions) ?? [:]
        shortcutActions = try container.decodeIfPresent([String: MouseAction].self, forKey: .shortcutActions) ?? [:]
    }
}
