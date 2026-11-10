import AppKit
@preconcurrency import CoreFoundation
@preconcurrency import CoreGraphics
import Foundation
import os

@MainActor
final class EventTapService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastAction: String?

    private let config: ConfigStore
    private let tagger: MouseKeyTagger
    private let logger = Logger(subsystem: "com.ericng.citillae510", category: "event-tap")
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressedButtons = Set<Int>()
    /// Key codes whose mouse press was turned into an action, so the matching
    /// key release can be swallowed too.
    private var pressedShortcutKeys = Set<UInt16>()
    private var pressedConsumerKeys = Set<Int32>()
    private var hasPromptedForAccessibility = false

    init(config: ConfigStore, tagger: MouseKeyTagger) {
        self.config = config
        self.tagger = tagger
    }

    /// Starts the event tap if Accessibility access has been granted. Safe to
    /// call repeatedly (for example after the user grants permission).
    func startIfNeeded() {
        guard !isRunning else { return }

        guard AXIsProcessTrusted() else {
            lastError = "Accessibility permission is required. Open Settings → Permissions."
            if !hasPromptedForAccessibility {
                hasPromptedForAccessibility = true
                _ = PermissionManager.requestAccessibility()
            }
            return
        }

        let eventTypes: [CGEventType] = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .keyDown, .keyUp,
            SystemDefinedEvent.type
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lastError = "Could not create the event tap. Check Accessibility permission, then press Retry."
            logger.error("CGEvent.tapCreate returned nil")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        isRunning = true
        lastError = nil
        logger.info("Event tap started")

        // The thumb buttons arrive as keystrokes from the mouse's own keyboard
        // interface, so the HID listener is what lets us tell them apart from
        // the real keyboard. That needs Input Monitoring as well.
        if !PermissionManager.hasInputMonitoring {
            PermissionManager.requestInputMonitoring()
        }
        tagger.start()
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
        pressedButtons.removeAll()
        pressedShortcutKeys.removeAll()
        pressedConsumerKeys.removeAll()
        isRunning = false
    }

    func restart() {
        stop()
        startIfNeeded()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.notice("Event tap was disabled by the system; re-enabled")
            }
            return Unmanaged.passUnretained(event)
        }

        // Never reprocess events we posted ourselves.
        if event.getIntegerValueField(.eventSourceUserData) == EventMarker.value {
            return Unmanaged.passUnretained(event)
        }

        guard config.config.enabled else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return handleMouseDown(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return handleMouseUp(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        case SystemDefinedEvent.type:
            return handleSystemDefined(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Mouse buttons

    private func handleMouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // CGEvent button numbers are 0-based; HID Button usages are 1-based.
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
        guard let action = config.config.action(for: button), action.isBound else {
            return Unmanaged.passUnretained(event)
        }
        if pressedButtons.contains(button) {
            return nil
        }
        pressedButtons.insert(button)
        trigger(button: button, action: action)
        return nil
    }

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
        if pressedButtons.remove(button) != nil {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Keys the mouse sends

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = ShortcutBinding.masked(event.flags)

        // A held mouse key repeats without new HID reports, so swallow the
        // repeat as well once its first press has been turned into an action.
        if pressedShortcutKeys.contains(keyCode) {
            return nil
        }

        // Match before claiming a sample. The mouse sends its modifier and key
        // as separate events, and the modifier's key-down must not use up the
        // tag meant for the key that follows it.
        guard let (binding, action) = config.config.action(forKeyboardKeyCode: keyCode, modifiers: modifiers),
              action.isBound else {
            return Unmanaged.passUnretained(event)
        }

        // Only keys the mouse itself just sent are candidates; the keyboard must
        // keep working exactly as before.
        guard tagger.claimKeyPress() != nil else {
            return Unmanaged.passUnretained(event)
        }

        pressedShortcutKeys.insert(keyCode)
        trigger(shortcut: binding, action: action)
        return nil
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        // Match on the key alone: the mouse may release its modifier before the
        // key itself, and the release still has to be swallowed.
        guard pressedShortcutKeys.remove(keyCode) != nil else {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    private func handleSystemDefined(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        let key = Int32((nsEvent.data1 >> 16) & 0xFFFF)
        // data1 holds the key type in bits 16-31 and the state in bits 8-15,
        // where 0xA is down and 0xB is up.
        let isDown = ((nsEvent.data1 >> 8) & 0xFF) == 0xA

        if !isDown {
            if pressedConsumerKeys.remove(key) != nil {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if pressedConsumerKeys.contains(key) {
            return nil
        }

        guard let (binding, action) = config.config.action(forConsumerKey: key),
              action.isBound else {
            return Unmanaged.passUnretained(event)
        }
        guard tagger.claimKeyPress() != nil else {
            return Unmanaged.passUnretained(event)
        }
        pressedConsumerKeys.insert(key)
        trigger(shortcut: binding, action: action)
        return nil
    }

    // MARK: - Acting

    private func trigger(button: Int, action: MouseAction) {
        lastAction = "Button \(button) → \(action.summary)"
        logger.debug("Button \(button, privacy: .public) triggered \(action.summary, privacy: .public)")
        ActionExecutor.perform(action, owner: .button(button))
    }

    private func trigger(shortcut: ShortcutBinding, action: MouseAction) {
        lastAction = "\(shortcut.name) → \(action.summary)"
        logger.debug("Mouse key \(shortcut.name, privacy: .public) triggered \(action.summary, privacy: .public)")
        ActionExecutor.perform(action, owner: .shortcut(shortcut.id))
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let service = Unmanaged<EventTapService>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated {
        service.handle(type: type, event: event)
    }
}
