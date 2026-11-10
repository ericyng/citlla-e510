import AppKit
import CoreGraphics
import Foundation
import os

/// The side effects a step needs, behind a protocol so tests can assert order,
/// timing and modifier release without posting real events.
///
/// Key and click events are split into down/up calls because the executor has to
/// press modifiers for real around a step: a system-wide shortcut (Mission
/// Control, Spotlight) and a chord click are matched against the modifier keys
/// that are actually down, not just the flags stamped on the event.
@MainActor
protocol EventSink: AnyObject, Sendable {
    /// One synthetic key event.
    func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags, isDown: Bool)
    /// One synthetic mouse button event at the current pointer location.
    func postMouseClick(_ kind: MouseClickKind, flags: CGEventFlags, isDown: Bool)
    /// A built-in system action: Dock notification, media key or shell.
    func postSystem(_ action: SystemAction)
    func openApp(at path: String)
    func openURL(_ string: String)
    func runShell(_ command: String)
}

@MainActor
enum ActionExecutor {
    /// Where steps post their events. The app uses the live sink; tests swap in
    /// a recording double so nothing real is posted.
    static var sink: any EventSink = LiveEventSink()

    /// Runs one action. Called on the main actor from the event tap, which must
    /// return immediately — anything that waits is handed to `MacroRunner`.
    static func perform(_ action: MouseAction, owner: MacroOwner) {
        guard action.isBound else { return }

        switch action.kind {
        case .sequence:
            // Handed off so the tap callback returns immediately.
            MacroRunner.run(action.steps, owner: owner, sink: sink)

        default:
            performStep(action.asStep, sink: sink)
        }
    }

    /// Runs one step synchronously.
    ///
    /// `MacroRunner` calls this between waits. A step is atomic: modifiers go
    /// down, the key or click is posted, and the modifiers come up in a `defer`,
    /// so no cancellation or early return can leave one held.
    ///
    /// `.none` and `.sequence` are no-ops: normalisation drops them before a run,
    /// and a direct caller gets an empty action rather than a recursion.
    static func performStep(_ step: ActionStep, sink: any EventSink) {
        switch step.kind {
        case .none, .sequence:
            return

        case .system:
            sink.postSystem(step.system)

        case .keyboardShortcut:
            guard step.hasShortcut else { return }
            postKey(step.keyCode, flags: KeyCodeMap.cgFlags(from: step.modifiers), sink: sink)

        case .mouseClick:
            postClick(step.click, modifiers: step.clickModifiers, sink: sink)

        case .openApp:
            sink.openApp(at: step.text)

        case .openURL:
            sink.openURL(step.text)

        case .shellCommand:
            sink.runShell(step.text)
        }
    }

    // MARK: - Synthetic events

    /// The four modifiers macOS matches system shortcuts against, in the order
    /// they are pressed. Releasing happens in reverse.
    private static let modifierKeys: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskControl, 59),     // left Control
        (.maskAlternate, 58),   // left Option
        (.maskShift, 56),       // left Shift
        (.maskCommand, 55)      // left Command
    ]

    /// Posts a keystroke with its modifiers held for real around it.
    ///
    /// Setting `CGEventFlags` on an event is enough for an application's own
    /// shortcuts, but system-wide shortcuts - Mission Control (⌃↑), App Exposé
    /// (⌃↓), Spotlight, screenshots - are matched against the modifier keys that
    /// are actually down. Posting the modifiers themselves is what makes those
    /// work. It is also what makes a remapped click a real ⌘-click or ⌥-click.
    ///
    /// Internal so `LiveEventSink` can drive the same helper for the built-in
    /// system actions; the release is in a `defer`, so a step that returns early
    /// cannot leave a modifier held.
    static func postKey(_ keyCode: UInt16, flags: CGEventFlags, sink: any EventSink) {
        withModifiers(flags, sink: sink) { held in
            sink.postKey(keyCode, flags: held, isDown: true)
            sink.postKey(keyCode, flags: held, isDown: false)
        }
    }

    private static func withModifiers(
        _ flags: CGEventFlags,
        sink: any EventSink,
        _ body: (CGEventFlags) -> Void
    ) {
        var held: CGEventFlags = []
        var pressed: [(flag: CGEventFlags, keyCode: CGKeyCode)] = []
        for modifier in modifierKeys where flags.contains(modifier.flag) {
            held.insert(modifier.flag)
            sink.postKey(modifier.keyCode, flags: held, isDown: true)
            pressed.append(modifier)
        }

        defer {
            for modifier in pressed.reversed() {
                held.remove(modifier.flag)
                sink.postKey(modifier.keyCode, flags: held, isDown: false)
            }
        }

        body(held)
    }

    private static func postClick(_ kind: MouseClickKind, modifiers: UInt, sink: any EventSink) {
        // A chord such as ⌘-click needs the modifiers down for real, the same
        // way the system shortcuts do, and the flags on each event so the app
        // under the cursor sees them too.
        withModifiers(KeyCodeMap.cgFlags(from: modifiers), sink: sink) { held in
            sink.postMouseClick(kind, flags: held, isDown: true)
            sink.postMouseClick(kind, flags: held, isDown: false)
        }
    }
}

/// The real sink: posts synthetic events with `EventMarker` stamped on them, so
/// the app's own event tap lets them through without re-processing them.
@MainActor
final class LiveEventSink: EventSink {
    private let logger = Logger(subsystem: "com.ericng.citillae510", category: "actions")

    func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags, isDown: Bool) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else {
            return
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: EventMarker.value)
        event.post(tap: .cghidEventTap)
    }

    func postMouseClick(_ kind: MouseClickKind, flags: CGEventFlags, isDown: Bool) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let location = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType
        switch kind {
        case .left:
            type = isDown ? .leftMouseDown : .leftMouseUp
        case .right:
            type = isDown ? .rightMouseDown : .rightMouseUp
        case .middle:
            type = isDown ? .otherMouseDown : .otherMouseUp
        }
        let button = CGMouseButton(rawValue: UInt32(kind.rawValue)) ?? .center

        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else {
            return
        }
        event.flags = flags
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(kind.rawValue))
        if isDown {
            // Every step is a fresh click, so two click steps never merge into
            // a double-click.
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        event.setIntegerValueField(.eventSourceUserData, value: EventMarker.value)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - System actions

    func postSystem(_ action: SystemAction) {
        switch action {
        case .back:
            ActionExecutor.postKey(33, flags: .maskCommand, sink: self)              // ⌘[
        case .forward:
            ActionExecutor.postKey(30, flags: .maskCommand, sink: self)              // ⌘]
        case .missionControl:
            DockControl.sendNotification("com.apple.expose.awake")
        case .appExpose:
            DockControl.showAppExpose()
        case .showDesktop:
            DockControl.sendNotification("com.apple.showdesktop.awake")
        case .launchpad:
            DockControl.sendNotification("com.apple.launchpad.toggle")
        case .spotlight:
            ActionExecutor.postKey(49, flags: .maskCommand, sink: self)              // ⌘Space
        case .screenshot:
            ActionExecutor.postKey(20, flags: [.maskCommand, .maskShift], sink: self) // ⌘⇧3
        case .lockScreen:
            ActionExecutor.postKey(12, flags: [.maskControl, .maskCommand], sink: self) // ⌃⌘Q
        case .sleepDisplay:
            runShell("/usr/bin/pmset displaysleepnow")
        case .volumeUp:
            postMediaKey(0)                               // NX_KEYTYPE_SOUND_UP
        case .volumeDown:
            postMediaKey(1)                               // NX_KEYTYPE_SOUND_DOWN
        case .mute:
            postMediaKey(7)                               // NX_KEYTYPE_MUTE
        case .playPause:
            postMediaKey(16)                              // NX_KEYTYPE_PLAY
        case .nextTrack:
            postMediaKey(17)                              // NX_KEYTYPE_NEXT
        case .previousTrack:
            postMediaKey(18)                              // NX_KEYTYPE_PREVIOUS
        }
    }

    private func postMediaKey(_ key: Int32) {
        // NX_SYSDEFINED: data1 = key << 16 | state << 8, where state 0xA is
        // down and 0xB is up. This is the standard way to synthesize the media
        // keys from an app without private APIs.
        for isDown in [true, false] {
            let state = isDown ? 0xA : 0xB
            let data1 = Int((key << 16) | (Int32(state) << 8))
            guard let nsEvent = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ), let cgEvent = nsEvent.cgEvent else { continue }
            cgEvent.setIntegerValueField(.eventSourceUserData, value: EventMarker.value)
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - App / URL / shell

    func openApp(at path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [logger] _, error in
            if let error {
                logger.error("Could not open \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func openURL(_ string: String) {
        guard !string.isEmpty, let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    func runShell(_ command: String) {
        guard !command.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.error("Could not run shell command: \(error.localizedDescription, privacy: .public)")
        }
    }
}
