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
    private let logger = Logger(subsystem: "com.ericng.citillae510", category: "event-tap")
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressedButtons = Set<Int>()
    private var hasPromptedForAccessibility = false

    init(config: ConfigStore) {
        self.config = config
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
            .otherMouseDown, .otherMouseUp
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
            // CGEvent button numbers are 0-based; HID Button usages are 1-based.
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            guard let action = config.config.action(for: button), action.isBound else {
                return Unmanaged.passUnretained(event)
            }
            if pressedButtons.contains(button) {
                return nil
            }
            pressedButtons.insert(button)
            lastAction = "Button \(button) → \(action.summary)"
            logger.debug("Button \(button, privacy: .public) triggered \(action.summary, privacy: .public)")
            ActionExecutor.perform(action)
            return nil

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            if pressedButtons.remove(button) != nil {
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
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
