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

    /// The mouse buttons this hardware actually sends. Everything else on the
    /// E510 (thumb buttons, the ninth control, DPI, tilt) arrives as a keystroke
    /// or stays in firmware, so there are no rows for buttons 4-8.
    static let reportedButtons: Set<Int> = [1, 2, 3]

    /// Rows older builds created for buttons this mouse never sends. Loading an
    /// old config drops them so the Buttons tab only lists real buttons.
    static let retiredButtons: Set<Int> = [4, 5, 6, 7, 8]

    /// The default layout: the three buttons the mouse reports, all passing
    /// through until the user assigns an action.
    static let defaults: [ButtonBinding] = reportedButtons.sorted().map {
        ButtonBinding(button: $0, action: .none)
    }
}
