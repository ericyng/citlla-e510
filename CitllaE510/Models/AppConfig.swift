import Foundation

struct AppConfig: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var bindings: [ButtonBinding] = ButtonBinding.defaults

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

    mutating func resetToDefaults() {
        bindings = ButtonBinding.defaults
    }

    init() {}

    // Be forgiving when loading configs written by older builds.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        bindings = try container.decodeIfPresent([ButtonBinding].self, forKey: .bindings) ?? ButtonBinding.defaults
    }
}
