import AppKit
import CoreGraphics
import Foundation

/// What one detected control means for the remapper.
enum TesterVerdict: Equatable {
    /// A mouse button number the event tap can bind.
    case bindable(button: Int, action: String?)
    /// Arrives as a real mouse button but has no binding.
    case unbound(button: Int)
    /// Recognised, but not a mouse button, so the current tap cannot touch it.
    case other(String)
}

struct TesterEvent: Identifiable {
    let id = UUID()
    let date: Date
    let category: String
    let summary: String
    let detail: String
    let controlKey: String
    let verdict: TesterVerdict
}

struct TesterControl: Identifiable {
    let id: String
    var label: String
    var detail: String
    var count: Int
    var verdict: TesterVerdict
    var lastSeen: Date
}

/// What one numbered control from the diagram has sent so far.
struct ControlHit: Equatable {
    var count = 0
    var last = Date.distantPast
    var detail = ""
    /// Mouse-button number, when the control turned out to be a plain button.
    var button: Int?
}

/// Watches every kind of event a mouse can produce - mouse buttons, wheel and
/// tilt, keyboard shortcuts, media keys - using a listen-only tap, so nothing
/// is suppressed or changed while the tester is open.
@MainActor
final class ButtonTester: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var events: [TesterEvent] = []
    @Published private(set) var controls: [TesterControl] = []
    @Published private(set) var hits: [Int: ControlHit] = [:]
    @Published private(set) var lastUnmapped: String?
    @Published private(set) var errorMessage: String?

    private let config: ConfigStore
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastScrollRecord = Date.distantPast
    private static let maxEvents = 120

    /// `NX_SYSDEFINED`. `CGEventType` has no Swift name for it.
    static let systemDefined = CGEventType(rawValue: 14)!

    init(config: ConfigStore) {
        self.config = config
    }

    func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else {
            errorMessage = "Accessibility permission is required before the tester can watch input."
            return
        }

        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .scrollWheel,
            .keyDown,
            Self.systemDefined
        ]
        let mask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: testerCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            errorMessage = "Could not create a listening event tap. Check Accessibility permission."
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        runLoopSource = source
        isRunning = true
        errorMessage = nil
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    func clear() {
        events.removeAll()
        controls.removeAll()
        hits.removeAll()
        lastUnmapped = nil
    }

    /// A plain-text summary that can be pasted into a bug report.
    func report() -> String {
        var lines = ["Citlla E510 button tester", "date: \(ISO8601DateFormatter().string(from: Date()))", ""]
        lines.append("Diagram controls:")
        for control in MouseMap.controls {
            if let hit = hits[control.number] {
                lines.append("  \(control.number). \(control.title): \(hit.detail)  x\(hit.count)")
            } else {
                lines.append("  \(control.number). \(control.title): (not seen)")
            }
        }
        lines.append("")
        lines.append("Detected events:")
        if controls.isEmpty {
            lines.append("  (none yet)")
        }
        for control in controls.sorted(by: { $0.label < $1.label }) {
            lines.append("  \(control.label)  x\(control.count)  - \(control.detail)")
        }
        lines.append("")
        lines.append("Last events:")
        for event in events.suffix(30) {
            lines.append("  \(event.category): \(event.summary)  [\(event.detail)]")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        // Ignore the events the remapper posts itself.
        if event.getIntegerValueField(.eventSourceUserData) == EventMarker.value {
            return
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            recordMouseButton(event, phase: "down")
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            recordMouseButton(event, phase: "up")
        case .scrollWheel:
            recordScroll(event)
        case .keyDown:
            recordKey(event)
        case Self.systemDefined:
            recordSystemDefined(event)
        default:
            break
        }
    }

    private func recordMouseButton(_ event: CGEvent, phase: String) {
        let raw = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let button = raw + 1
        let name = ButtonBinding(button: button, action: .none).name
        let verdict = verdictForButton(button)
        let action: String
        switch verdict {
        case let .bindable(_, summary):
            action = summary.map { "remaps to \($0)" } ?? "bound"
        case .unbound:
            action = "no binding, passes through"
        case .other:
            action = ""
        }

        record(
            category: "Mouse",
            summary: "\(name) \(phase)",
            detail: "CGEvent button \(raw) (1-based \(button)) \(action)",
            controlKey: "mouse-\(button)",
            label: name,
            verdict: verdict,
            control: MouseMap.control(forButton: button)?.number,
            button: button,
            // A press and its release both belong to the control; only the press
            // counts, so the tally matches the number of presses.
            counts: phase == "down"
        )
    }

    private func recordScroll(_ event: CGEvent) {
        let now = Date()
        guard now.timeIntervalSince(lastScrollRecord) > 0.12 else { return }
        lastScrollRecord = now

        let vertical = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let horizontal = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let pointing = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        if horizontal != 0 || pointing != 0 {
            let direction = (horizontal + pointing) < 0 ? "left" : "right"
            record(
                category: "Scroll",
                summary: "Tilt \(direction)",
                detail: "horizontal delta \(horizontal)/\(pointing), vertical \(vertical)",
                controlKey: "tilt-\(direction)",
                label: "Tilt \(direction)",
                verdict: .other("Horizontal scroll/tilt. The remapper does not handle scroll events yet."),
                control: 5
            )
        } else {
            let direction = vertical < 0 ? "down" : "up"
            record(
                category: "Scroll",
                summary: "Vertical \(direction)",
                detail: "delta \(vertical)\(continuous ? ", continuous" : "")",
                controlKey: "scroll-v",
                label: "Wheel",
                verdict: .other("Normal scrolling, passed through."),
                control: 3
            )
        }
    }

    private func recordKey(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        var modifierBits: UInt = 0
        if flags.contains(.maskControl) { modifierBits |= NSEvent.ModifierFlags.control.rawValue }
        if flags.contains(.maskAlternate) { modifierBits |= NSEvent.ModifierFlags.option.rawValue }
        if flags.contains(.maskShift) { modifierBits |= NSEvent.ModifierFlags.shift.rawValue }
        if flags.contains(.maskCommand) { modifierBits |= NSEvent.ModifierFlags.command.rawValue }

        let shortcut = KeyCodeMap.describe(keyCode: keyCode, modifiers: modifierBits)
        record(
            category: "Keyboard",
            summary: shortcut,
            detail: "key code \(keyCode) from \(eventSourceName(event))",
            controlKey: "key-\(keyCode)-\(modifierBits)",
            label: shortcut,
            verdict: .other("This arrived as a keyboard shortcut, not a mouse button. Use the mouse's own software to switch it out of shortcut mode, or bind the shortcut itself."),
            control: MouseMap.control(forKeyCode: keyCode, modifiers: modifierBits)?.number,
            // A shortcut from the physical keyboard is not a mouse control, so
            // it must not be reported as "not on the diagram".
            flagsUnmapped: false
        )
    }

    private func recordSystemDefined(_ event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event) else { return }
        let keyType = Int32((nsEvent.data1 >> 16) & 0xFFFF)
        let isDown = ((nsEvent.data1 >> 8) & 0x1) == 0x1
        let name = Self.mediaKeyNames[keyType] ?? "NX key \(keyType)"

        record(
            category: "System",
            summary: "\(name) \(isDown ? "down" : "up")",
            detail: "system-defined key type \(keyType)",
            controlKey: "sys-\(keyType)",
            label: name,
            verdict: .other("A media/system key, not a mouse button. The current tap cannot bind it."),
            flagsUnmapped: false
        )
    }

    private func verdictForButton(_ button: Int) -> TesterVerdict {
        let action = config.binding(for: button).action
        return action.isBound
            ? .bindable(button: button, action: action.summary)
            : .unbound(button: button)
    }

    private func eventSourceName(_ event: CGEvent) -> String {
        guard let source = event.getIntegerValueField(.eventSourceStateID) as Int64? else { return "unknown" }
        switch source {
        case 0: return "HID system"
        case 1: return "private"
        default: return "state \(source)"
        }
    }

    private func record(
        category: String,
        summary: String,
        detail: String,
        controlKey: String,
        label: String,
        verdict: TesterVerdict,
        control: Int? = nil,
        button: Int? = nil,
        counts: Bool = true,
        flagsUnmapped: Bool = true
    ) {
        let entry = TesterEvent(
            date: Date(),
            category: category,
            summary: summary,
            detail: detail,
            controlKey: controlKey,
            verdict: verdict
        )
        events.append(entry)
        if events.count > Self.maxEvents {
            events.removeFirst(events.count - Self.maxEvents)
        }

        if let index = controls.firstIndex(where: { $0.id == controlKey }) {
            controls[index].count += 1
            controls[index].lastSeen = Date()
            controls[index].verdict = verdict
            controls[index].detail = detail
        } else {
            controls.append(
                TesterControl(
                    id: controlKey,
                    label: label,
                    detail: detail,
                    count: 1,
                    verdict: verdict,
                    lastSeen: Date()
                )
            )
        }
        controls.sort { $0.lastSeen > $1.lastSeen }

        if let control {
            guard counts else { return }
            var hit = hits[control] ?? ControlHit()
            hit.count += 1
            hit.last = Date()
            hit.detail = label
            if let button { hit.button = button }
            hits[control] = hit
        } else if flagsUnmapped {
            lastUnmapped = "\(category): \(summary)"
        }
    }

    private static let mediaKeyNames: [Int32: String] = [
        0: "Volume Up",
        1: "Volume Down",
        2: "Brightness Up",
        3: "Brightness Down",
        4: "Caps Lock",
        6: "Power",
        7: "Video Mirror",
        16: "Play/Pause",
        17: "Next Track",
        18: "Previous Track",
        19: "Fast Forward",
        20: "Rewind"
    ]
}

private let testerCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let tester = Unmanaged<ButtonTester>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap's run loop source is installed on the main run loop, so this
    // callback always runs on the main thread. `EventBox` only exists to tell
    // the compiler that the borrowed CGEvent is not crossing a concurrency
    // boundary, which it is not.
    let box = EventBox(type: type, event: event)
    MainActor.assumeIsolated {
        tester.handle(type: box.type, event: box.event)
    }
    return Unmanaged.passUnretained(event)
}

private struct EventBox: @unchecked Sendable {
    let type: CGEventType
    let event: CGEvent
}
