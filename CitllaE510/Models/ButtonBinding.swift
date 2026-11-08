import Foundation

/// One physical mouse button (1-based, matching the HID Button usage) and the
/// action assigned to it.
struct ButtonBinding: Codable, Identifiable, Equatable, Sendable {
    var button: Int
    var action: MouseAction

    var id: Int { button }

    var name: String {
        switch button {
        case 1: "Left Click"
        case 2: "Right Click"
        case 3: "Middle Click"
        case 4: "Button 4"
        case 5: "Button 5"
        case 6: "Button 6"
        case 7: "Button 7"
        case 8: "Button 8"
        default: "Button \(button)"
        }
    }

    var subtitle: String {
        switch button {
        case 1: "Primary button"
        case 2: "Secondary button"
        case 3: "Scroll wheel click"
        case 4: "Usually the rear side button"
        case 5: "Usually the front side button"
        case 6, 7, 8: "Extra button reported by the mouse"
        default: "Extra mouse button"
        }
    }

    /// The default layout for the CITLLA PRO MAX E510's eight-button report.
    /// The two side buttons become browser/Explorer back and forward; the
    /// remaining extra buttons are left unbound until the user assigns them.
    static let defaults: [ButtonBinding] = (1...8).map { button in
        let action: MouseAction
        switch button {
        case 4:
            action = MouseAction(kind: .system, system: .back)
        case 5:
            action = MouseAction(kind: .system, system: .forward)
        default:
            action = .none
        }
        return ButtonBinding(button: button, action: action)
    }
}
