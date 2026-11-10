import Foundation

/// A per-app override of the global button and mouse-key map.
///
/// Types only for now: the contract commit freezes the shape so the app-shell
/// and profiles tracks cannot drift, and the profiles track implements the
/// storage and the lookup. Nothing reads this yet, so behaviour is unchanged.
///
/// A profile is identified by bundle identifier, which is what
/// `NSWorkspace.didActivateApplicationNotification` reports. The global mapping
/// stays the default: a button or key the profile does not mention falls back to
/// it, and a disabled profile is ignored entirely.
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
}
