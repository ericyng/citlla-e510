import AppKit
import CoreGraphics
import Foundation

/// What one detected control means for the remapper.
enum TesterVerdict: Equatable {
    /// A mouse button number the event tap can bind.
    case bindable(button: Int, action: String?)
    /// Arrives as a real mouse button but has no binding.
    case unbound(button: Int)
    /// The mouse sent a keystroke or media key that the remapper can bind.
    case bindableKey(trigger: String, action: String?)
    /// The mouse sent a keystroke or media key with no binding yet.
    case unboundKey(trigger: String)
    /// Recognised, but the remapper does not handle it.
    case other(String)

    var isBindable: Bool {
        switch self {
        case .bindable, .bindableKey: true
        case .unbound, .unboundKey, .other: false
        }
    }
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

/// The steps of a sequence the tester is watching, and which one is firing.
///
/// The tester never posts events; the remapper owns the real run. To report
/// progress the tester asks `MacroRunner` to run the same steps against a sink
/// that does nothing, so the `onStep` callback arrives in lockstep with the
/// real run without a second set of clicks or keystrokes reaching the system.
struct SequenceProgress: Equatable {
    /// The control that started the run, e.g. "Middle Click" or "⌃←".
    let label: String
    /// The steps that will actually fire, after normalisation and the caps.
    let steps: [ActionStep]
    /// Index of the step currently firing; `nil` before the first one.
    var current: Int?
    var finished = false

    var total: Int { steps.count }

    /// 1-based number for display, matching the step list.
    var currentNumber: Int? { current.map { $0 + 1 } }
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
    /// Progress of the last sequence a bound control ran while the tester was
    /// watching, so the window can count and highlight steps.
    @Published private(set) var sequenceProgress: SequenceProgress?

    private let config: ConfigStore
    private let tagger: MouseKeyTagger
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastScrollRecord = Date.distantPast
    private static let maxEvents = 120

    /// Mirror runs are keyed separately from the remapper's real runs, so the
    /// preview can never cancel (or be cancelled by) the action actually firing.
    private static let previewOwner = MacroOwner.other("tester-preview")
    /// Identifies the current preview, so a step from a replaced run cannot
    /// highlight the wrong row.
    private var previewToken = UUID()

    init(config: ConfigStore, tagger: MouseKeyTagger) {
        self.config = config
        self.tagger = tagger
    }

    func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else {
            errorMessage = "Accessibility permission is required before the tester can watch input."
            return
        }

        // The tester shares the remapper's listener. Starting it here as well
        // means the tester still explains mouse-sent keys when the event tap has
        // not been started yet.
        if !PermissionManager.hasInputMonitoring {
            PermissionManager.requestInputMonitoring()
        }
        tagger.start()

        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .scrollWheel,
            .keyDown,
            SystemDefinedEvent.type
        ]
        let mask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            // Head insert so the tester still sees a button that the remapper
            // (created earlier) swallows a moment later. A listen-only tap
            // cannot suppress anything, so this is safe.
            place: .headInsertEventTap,
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
        MacroRunner.cancel(owner: Self.previewOwner)
        sequenceProgress = nil
        previewToken = UUID()
    }

    func clear() {
        events.removeAll()
        controls.removeAll()
        hits.removeAll()
        lastUnmapped = nil
        MacroRunner.cancel(owner: Self.previewOwner)
        sequenceProgress = nil
        previewToken = UUID()
    }

    /// A plain-text summary that can be pasted into a bug report.
    func report() -> String {
        var lines = ["Citlla E510 button tester", "date: \(ISO8601DateFormatter().string(from: Date()))", ""]
        lines.append("HID listener: \(tagger.isRunning ? "running" : "not running") · \(tagger.deviceCount) device(s)")
        if let error = tagger.openError {
            lines.append("HID open error: \(error)")
        }
        lines.append("")
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
        case SystemDefinedEvent.type:
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
        case .bindableKey, .unboundKey, .other:
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

        if phase == "down" {
            previewIfNeeded(config.binding(for: button).action, label: name)
        }
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
        let modifiers = ShortcutBinding.masked(event.flags)
        let shortcut = KeyCodeMap.describe(keyCode: keyCode, modifiers: modifiers)

        // The tester's tap is ahead of the remapper's, so peek rather than claim:
        // the remapper still needs this sample to do its own attribution.
        let sample = tagger.peekKeyPress()

        let category: String
        let detail: String
        let verdict: TesterVerdict
        if let sample {
            category = "Mouse key"
            if let (_, action) = config.config.action(forKeyboardKeyCode: keyCode, modifiers: modifiers),
               action.isBound {
                verdict = .bindableKey(trigger: shortcut, action: action.summary)
                detail = "key code \(keyCode), remaps to \(action.summary) · \(sample.summary)"
            } else {
                verdict = .unboundKey(trigger: shortcut)
                detail = "key code \(keyCode), no binding yet · \(sample.summary)"
            }
        } else {
            category = "Keyboard"
            detail = "key code \(keyCode) from \(eventSourceName(event))"
            verdict = .other("This came from the keyboard. Only keystrokes the mouse itself sends are remapped.")
        }

        record(
            category: category,
            summary: shortcut,
            detail: detail,
            controlKey: "key-\(keyCode)-\(modifiers)",
            label: shortcut,
            verdict: verdict,
            control: sample == nil ? nil : MouseMap.control(forKeyCode: keyCode, modifiers: modifiers)?.number,
            // A shortcut from the physical keyboard is not a mouse control, so
            // it must not be reported as "not on the diagram".
            flagsUnmapped: sample != nil
        )

        if sample != nil,
           let (_, action) = config.config.action(forKeyboardKeyCode: keyCode, modifiers: modifiers) {
            previewIfNeeded(action, label: shortcut)
        }
    }

    private func recordSystemDefined(_ event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event) else { return }
        let data1 = Int(nsEvent.data1)
        let keyType = NXKeyState.keyType(from: data1)
        let isDown = NXKeyState.isDown(data1)
        let name = ShortcutBinding.consumerName(keyType)
        let sample = tagger.peekKeyPress()

        let category: String
        let detail: String
        let verdict: TesterVerdict
        if let sample {
            category = "Mouse key"
            if let (_, action) = config.config.action(forConsumerKey: keyType), action.isBound {
                verdict = .bindableKey(trigger: name, action: action.summary)
                detail = "media key \(keyType), remaps to \(action.summary) · \(sample.summary)"
            } else {
                verdict = .unboundKey(trigger: name)
                detail = "media key \(keyType), no binding yet · \(sample.summary)"
            }
        } else {
            category = "System"
            detail = "system-defined key type \(keyType)"
            verdict = .other("A media/system key, not a mouse button.")
        }

        record(
            category: category,
            summary: "\(name) \(isDown ? "down" : "up")",
            detail: detail,
            controlKey: "sys-\(keyType)",
            label: name,
            verdict: verdict,
            counts: isDown,
            flagsUnmapped: sample != nil && isDown
        )

        if isDown, sample != nil, let (_, action) = config.config.action(forConsumerKey: keyType) {
            previewIfNeeded(action, label: name)
        }
    }

    private func verdictForButton(_ button: Int) -> TesterVerdict {
        let action = config.binding(for: button).action
        return action.isBound
            ? .bindable(button: button, action: action.summary)
            : .unbound(button: button)
    }

    // MARK: - Sequence progress

    /// Mirrors a sequence run so the window can count steps and highlight the
    /// one that is firing.
    ///
    /// The run is handed to `MacroRunner` on the main actor with a silent sink,
    /// so nothing is posted, the tap and the UI never wait, and the reported
    /// steps arrive with the runner's own delays and caps. A second press of the
    /// same control replaces the preview, exactly as it replaces the real run.
    private func previewIfNeeded(_ action: MouseAction, label: String) {
        guard isRunning, action.kind == .sequence else { return }

        let planned = MacroRunner.plan(for: action.steps)
        guard !planned.isEmpty else { return }

        let token = UUID()
        previewToken = token
        sequenceProgress = SequenceProgress(
            label: label,
            steps: planned.map(\.step),
            current: nil
        )

        MacroRunner.run(
            action.steps,
            owner: Self.previewOwner,
            onStep: { [weak self] index in
                guard let self, self.previewToken == token else { return }
                self.sequenceStepFired(index)
            },
            sink: SilentEventSink.shared
        )
    }

    private func sequenceStepFired(_ index: Int) {
        guard var progress = sequenceProgress,
              progress.steps.indices.contains(index) else { return }
        progress.current = index
        progress.finished = index == progress.steps.count - 1
        sequenceProgress = progress
    }

    private func eventSourceName(_ event: CGEvent) -> String {
        // CGEventSourceStateID: private -1, combined session 0, HID system 1.
        let state = event.getIntegerValueField(.eventSourceStateID)
        switch state {
        case -1: return "private"
        case 0: return "combined session"
        case 1: return "HID system"
        default: return "state \(state)"
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

/// A sink that records nothing, for the tester's step preview.
///
/// `MacroRunner` only distinguishes steps by calling the sink; handing it this
/// one lets the tester receive `onStep` for a run that touches nothing, so the
/// real click or keystroke still comes from the remapper alone.
@MainActor
private final class SilentEventSink: EventSink {
    static let shared = SilentEventSink()

    func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags, isDown: Bool) {}
    func postMouseClick(_ kind: MouseClickKind, flags: CGEventFlags, isDown: Bool) {}
    func postSystem(_ action: SystemAction) {}
    func openApp(at path: String) {}
    func openURL(_ string: String) {}
    func runShell(_ command: String) {}
}
