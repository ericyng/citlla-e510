import AppKit
import Foundation
import os

/// `--perform <system-action>` runs one built-in action and exits.
///
/// Debug helper for the same reason `--status` exists: posting synthetic events
/// needs Accessibility, and a terminal run borrows the terminal's grants
/// instead of the app's. Running the probe through `open` exercises the action
/// with exactly the permissions the app has.
///
/// `--post-shortcut <keycode> <modifierMask> <variant>` posts one keystroke
/// using a specific event-source/tap combination. Used to find out which
/// combination the system hotkey handler actually honours - it honours none of
/// them, which is why `DockControl` exists.
///
/// `--coredock <notification>` sends one Dock notification.
enum ActionProbe {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments

        if let flag = args.firstIndex(of: "--post-shortcut") {
            guard flag + 3 < args.count,
                  let keyCode = UInt16(args[flag + 1]),
                  let mask = UInt64(args[flag + 2]),
                  let variant = Int(args[flag + 3]) else {
                print("usage: --post-shortcut <keycode> <modifierMask> <variant>")
                exit(2)
            }
            let logger = Logger(subsystem: "com.ericng.citillae510", category: "probe")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                post(keyCode: keyCode, flags: CGEventFlags(rawValue: mask), variant: variant, logger: logger)
                try? await Task.sleep(for: .milliseconds(1500))
                exit(0)
            }
            return true
        }

        if let flag = args.firstIndex(of: "--coredock") {
            guard flag + 1 < args.count else {
                print("usage: --coredock <notification>")
                exit(2)
            }
            let notification = args[flag + 1]
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                DockControl.sendNotification(notification)
                try? await Task.sleep(for: .milliseconds(1500))
                exit(0)
            }
            return true
        }

        guard let flag = args.firstIndex(of: "--perform"), flag + 1 < args.count else { return false }

        let name = args[flag + 1]
        guard let system = SystemAction(rawValue: name) else {
            print("unknown system action: \(name)")
            exit(2)
        }

        Task { @MainActor in
            // Give the run loop a moment so the app is a normal, fully
            // launched process before it posts anything.
            try? await Task.sleep(for: .milliseconds(500))
            ActionExecutor.perform(MouseAction(kind: .system, system: system), owner: .other("perform"))
            try? await Task.sleep(for: .milliseconds(1500))
            exit(0)
        }
        return true
    }

    // MARK: - Variants

    private static func post(keyCode: UInt16, flags: CGEventFlags, variant: Int, logger: Logger) {
        let sourceState: CGEventSourceStateID
        let tap: CGEventTapLocation
        let marker: Bool

        switch variant {
        case 0: (sourceState, tap, marker) = (.hidSystemState, .cghidEventTap, true)
        case 1: (sourceState, tap, marker) = (.combinedSessionState, .cghidEventTap, true)
        case 2: (sourceState, tap, marker) = (.privateState, .cghidEventTap, true)
        case 3: (sourceState, tap, marker) = (.hidSystemState, .cgSessionEventTap, true)
        case 4: (sourceState, tap, marker) = (.hidSystemState, .cghidEventTap, false)
        case 5: (sourceState, tap, marker) = (.combinedSessionState, .cgAnnotatedSessionEventTap, true)
        default: (sourceState, tap, marker) = (.hidSystemState, .cghidEventTap, true)
        }

        let modifiers: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
            (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55)
        ]
        var held: CGEventFlags = []
        var pressed: [(flag: CGEventFlags, keyCode: CGKeyCode)] = []
        for modifier in modifiers where flags.contains(modifier.flag) {
            held.insert(modifier.flag)
            send(modifier.keyCode, flags: held, isDown: true, sourceState: sourceState, tap: tap, marker: marker, logger: logger)
            pressed.append(modifier)
        }
        send(keyCode, flags: held, isDown: true, sourceState: sourceState, tap: tap, marker: marker, logger: logger)
        send(keyCode, flags: held, isDown: false, sourceState: sourceState, tap: tap, marker: marker, logger: logger)
        for modifier in pressed.reversed() {
            held.remove(modifier.flag)
            send(modifier.keyCode, flags: held, isDown: false, sourceState: sourceState, tap: tap, marker: marker, logger: logger)
        }
        logger.notice("Probe posted variant \(variant, privacy: .public): key=\(keyCode, privacy: .public) flags=\(flags.rawValue, privacy: .public)")
    }

    private static func send(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags,
        isDown: Bool,
        sourceState: CGEventSourceStateID,
        tap: CGEventTapLocation,
        marker: Bool,
        logger: Logger
    ) {
        guard let source = CGEventSource(stateID: sourceState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else {
            logger.error("Probe could not create an event")
            return
        }
        event.flags = flags
        if marker {
            event.setIntegerValueField(.eventSourceUserData, value: EventMarker.value)
        }
        event.post(tap: tap)
    }
}
