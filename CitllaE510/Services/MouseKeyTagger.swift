import Foundation
@preconcurrency import IOKit.hid
import os

/// One key press seen on the mouse's own HID interface.
struct MouseKeySample: Sendable {
    let date: Date
    let usagePage: Int
    let usage: Int
    /// 1 for a press, 0 for a release.
    let value: Int

    var isConsumer: Bool { usagePage == 0x0C }

    var summary: String {
        switch usagePage {
        case 0x07: "HID key usage 0x" + String(usage, radix: 16)
        case 0x0C: "HID consumer usage 0x" + String(usage, radix: 16)
        default: "usage page 0x" + String(usagePage, radix: 16) + " usage 0x" + String(usage, radix: 16)
        }
    }
}

/// Recognises key presses that came from the mouse instead of the keyboard.
///
/// The CITLLA E510's receiver presents two HID interfaces: a mouse and a
/// keyboard. The extra buttons are on the keyboard one, so macOS turns them into
/// real keystrokes and an ordinary `CGEvent` tap has no way to tell them apart
/// from the keyboard.
///
/// This class listens to the mouse's own HID reports on a background run loop
/// and keeps a short history. When a key press reaches the event tap a few
/// milliseconds later, `claimKeyPress()` reports whether the mouse is the one
/// that sent it.
///
/// It opens the device for reading only - nothing is seized or suppressed here,
/// so normal mouse and keyboard use is unaffected.
final class MouseKeyTagger: @unchecked Sendable {
    static let vendorID = 0x1EA7
    static let productID = 0x66

    /// How long after a HID report a key event is still attributed to the mouse.
    /// Reports land a couple of milliseconds before the event; the window is
    /// short enough that a real keystroke pressed at the same moment is not
    /// mistaken for one from the mouse.
    static let attributionWindow: TimeInterval = 0.12

    private struct State {
        var manager: IOHIDManager?
        var runLoop: CFRunLoop?
        var thread: Thread?
        var shouldStop = false
        var samples: [MouseKeySample] = []
        var openResult: IOReturn = kIOReturnSuccess
        var devices = 0
    }

    private let lock = NSLock()
    private var state = State()
    private let logger = Logger(subsystem: "com.ericng.citillae510", category: "hid")

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.manager != nil
    }

    var openError: IOReturn? {
        lock.lock()
        defer { lock.unlock() }
        return state.openResult == kIOReturnSuccess ? nil : state.openResult
    }

    var deviceCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return state.devices
    }

    // MARK: - Lifecycle

    func start() {
        lock.lock()
        guard state.manager == nil, state.thread == nil else {
            lock.unlock()
            return
        }
        state.shouldStop = false
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "Citlla mouse HID listener"
        thread.qualityOfService = .userInteractive
        state.thread = thread
        lock.unlock()

        thread.start()
    }

    func stop() {
        lock.lock()
        state.shouldStop = true
        let runLoop = state.runLoop
        lock.unlock()
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    private func run() {
        var lastLoggedResult: IOReturn?
        var failedOpenAttempts = 0

        while true {
            lock.lock()
            let shouldStop = state.shouldStop
            lock.unlock()
            if shouldStop { break }

            // Opening the device without Input Monitoring makes the HID system
            // write a TCC denial every time, so wait for the grant before
            // trying at all and poll for it cheaply instead.
            guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
                let notPermitted = kIOReturnNotPermitted
                lock.lock()
                state.openResult = notPermitted
                lock.unlock()
                if lastLoggedResult != notPermitted {
                    logger.notice("Waiting for Input Monitoring before listening to the mouse")
                    lastLoggedResult = notPermitted
                }
                sleepUnlessStopped(for: 2)
                continue
            }

            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matches: [[String: Any]] = [
                [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID]
            ]
            IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, taggerDeviceAdded, Unmanaged.passUnretained(self).toOpaque())
            IOHIDManagerRegisterInputValueCallback(manager, taggerValueReceived, Unmanaged.passUnretained(self).toOpaque())

            let runLoop = CFRunLoopGetCurrent()!
            IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

            if result == kIOReturnSuccess {
                lock.lock()
                state.openResult = result
                state.manager = manager
                state.runLoop = runLoop
                lock.unlock()
                lastLoggedResult = nil
                failedOpenAttempts = 0
                logger.info("Mouse HID listener started")
                CFRunLoopRun()
            } else {
                lock.lock()
                state.openResult = result
                lock.unlock()
                if lastLoggedResult != result {
                    logger.error("Could not open the mouse for listening: \(result, privacy: .public)")
                    lastLoggedResult = result
                }
            }

            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

            lock.lock()
            state.manager = nil
            state.runLoop = nil
            lock.unlock()

            lock.lock()
            let stopRequested = state.shouldStop
            lock.unlock()
            if stopRequested { break }

            // The device can be missing for a moment while the receiver
            // re-enumerates, so keep trying - but back off instead of retrying
            // every second forever.
            if result != kIOReturnSuccess {
                failedOpenAttempts += 1
                let delay = min(pow(2, Double(failedOpenAttempts - 1)), 8)
                sleepUnlessStopped(for: delay)
            }
        }

        lock.lock()
        state.manager = nil
        state.runLoop = nil
        state.thread = nil
        lock.unlock()
    }

    /// Sleeps in small steps so `stop()` takes effect promptly.
    private func sleepUnlessStopped(for interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            lock.lock()
            let shouldStop = state.shouldStop
            lock.unlock()
            if shouldStop { return }
            Thread.sleep(forTimeInterval: min(0.25, deadline.timeIntervalSinceNow))
        }
    }

    // MARK: - Attribution

    /// Claims the most recent key press the mouse sent, if it is recent enough.
    ///
    /// Each key press is claimed once, so a single HID report can account for
    /// exactly one key event.
    func claimKeyPress(within window: TimeInterval = MouseKeyTagger.attributionWindow) -> MouseKeySample? {
        let cutoff = Date().addingTimeInterval(-window)
        lock.lock()
        defer { lock.unlock() }
        // Oldest first: a chord sends its modifier before its key.
        while let sample = state.samples.first {
            state.samples.removeFirst()
            if sample.date >= cutoff {
                return sample
            }
        }
        return nil
    }

    /// Looks for a recent key press without consuming it.
    ///
    /// The tester's listen-only tap runs ahead of the remapper's tap, so it must
    /// look without claiming: the remapper still needs the sample a moment later.
    func peekKeyPress(within window: TimeInterval = MouseKeyTagger.attributionWindow) -> MouseKeySample? {
        let cutoff = Date().addingTimeInterval(-window)
        lock.lock()
        defer { lock.unlock() }
        return state.samples.last { $0.date >= cutoff }
    }

    /// The key presses the mouse sent recently, newest last. Used by the tester.
    func recentSamples(limit: Int = 8) -> [MouseKeySample] {
        lock.lock()
        defer { lock.unlock() }
        return Array(state.samples.suffix(limit))
    }

    fileprivate func noteDevice() {
        lock.lock()
        state.devices += 1
        lock.unlock()
    }

    fileprivate func record(usagePage: Int, usage: Int, value: Int) {
        // Only the keyboard and consumer collections matter; pointer movement
        // and the mouse's own buttons are handled by the event tap.
        guard usagePage == 0x07 || usagePage == 0x0C else { return }
        // Ignore releases; they only matter to the event tap for suppression.
        guard value != 0 else { return }

        let sample = MouseKeySample(date: Date(), usagePage: usagePage, usage: usage, value: value)
        lock.lock()
        state.samples.append(sample)
        let cutoff = Date().addingTimeInterval(-2)
        state.samples.removeAll { $0.date < cutoff }
        if state.samples.count > 32 {
            state.samples.removeFirst(state.samples.count - 32)
        }
        lock.unlock()
    }
}

private func taggerDeviceAdded(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ device: IOHIDDevice
) {
    guard let context else { return }
    let tagger = Unmanaged<MouseKeyTagger>.fromOpaque(context).takeUnretainedValue()
    tagger.noteDevice()
}

private func taggerValueReceived(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ value: IOHIDValue
) {
    guard let context else { return }
    let element = IOHIDValueGetElement(value)
    let page = Int(IOHIDElementGetUsagePage(element))
    let usage = Int(IOHIDElementGetUsage(element))
    let integerValue = Int(IOHIDValueGetIntegerValue(value))
    let tagger = Unmanaged<MouseKeyTagger>.fromOpaque(context).takeUnretainedValue()
    tagger.record(usagePage: page, usage: usage, value: integerValue)
}
