import AppKit
import CoreGraphics
import Foundation
import os

enum ActionExecutor {
    private static let logger = Logger(subsystem: "com.ericng.citillae510", category: "actions")

    static func perform(_ action: MouseAction) {
        guard action.isBound else { return }

        switch action.kind {
        case .none:
            break

        case .system:
            performSystem(action.system)

        case .keyboardShortcut:
            guard action.hasShortcut else { return }
            postKey(action.keyCode, flags: KeyCodeMap.cgFlags(from: action.modifiers))

        case .mouseClick:
            postClick(action.click)

        case .openApp:
            openApp(at: action.text)

        case .openURL:
            openURL(action.text)

        case .shellCommand:
            runShell(action.text)
        }
    }

    // MARK: - System actions

    private static func performSystem(_ action: SystemAction) {
        switch action {
        case .back:
            postKey(33, flags: .maskCommand)              // ⌘[
        case .forward:
            postKey(30, flags: .maskCommand)              // ⌘]
        case .missionControl:
            postKey(126, flags: .maskControl)             // ⌃↑
        case .appExpose:
            postKey(125, flags: .maskControl)             // ⌃↓
        case .showDesktop:
            postKey(103, flags: [])                       // F11
        case .launchpad:
            // macOS 26+ replaced Launchpad.app with Apps.app; support both.
            let launchpad = "/System/Applications/Launchpad.app"
            let apps = "/System/Applications/Apps.app"
            if FileManager.default.fileExists(atPath: launchpad) {
                openApp(at: launchpad)
            } else if FileManager.default.fileExists(atPath: apps) {
                openApp(at: apps)
            } else {
                postKey(118, flags: [])                   // F4
            }
        case .spotlight:
            postKey(49, flags: .maskCommand)              // ⌘Space
        case .screenshot:
            postKey(20, flags: [.maskCommand, .maskShift]) // ⌘⇧3
        case .lockScreen:
            postKey(12, flags: [.maskControl, .maskCommand]) // ⌃⌘Q
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

    // MARK: - Synthetic events

    private static func postKey(_ keyCode: UInt16, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: EventMarker.value)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func postMediaKey(_ key: Int32) {
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

    private static func postClick(_ kind: MouseClickKind) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let location = CGEvent(source: nil)?.location ?? .zero
        let downType: CGEventType
        let upType: CGEventType
        switch kind {
        case .left:
            downType = .leftMouseDown
            upType = .leftMouseUp
        case .right:
            downType = .rightMouseDown
            upType = .rightMouseUp
        case .middle:
            downType = .otherMouseDown
            upType = .otherMouseUp
        }
        let button = CGMouseButton(rawValue: UInt32(kind.rawValue)) ?? .center

        for (type, isDown) in [(downType, true), (upType, false)] {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: location,
                mouseButton: button
            ) else { continue }
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(kind.rawValue))
            if isDown {
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            event.setIntegerValueField(.eventSourceUserData, value: EventMarker.value)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - App / URL / shell

    private static func openApp(at path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                logger.error("Could not open \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func openURL(_ string: String) {
        guard let url = URL(string: string), !string.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }

    private static func runShell(_ command: String) {
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
