import Foundation
@preconcurrency import IOKit.hid
import os

struct HIDDeviceInfo: Identifiable, Hashable, Sendable {
    let id: UInt64
    let name: String
    let vendorID: Int
    let productID: Int
    let usagePage: Int
    let usage: Int

    var transportDescription: String {
        String(format: "VID 0x%04X · PID 0x%04X", vendorID, productID)
    }

    var usageDescription: String {
        String(format: "usage page 0x%04X · usage 0x%04X", usagePage, usage)
    }
}

struct HIDEventEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let date = Date()
    let device: String
    let usagePage: Int
    let usage: Int
    let value: Int

    var usagePageName: String {
        switch usagePage {
        case 0x01: "Generic Desktop"
        case 0x09: "Button"
        case 0x0C: "Consumer"
        case 0xFFB5: "Vendor"
        default: String(format: "Page 0x%04X", usagePage)
        }
    }

    var summary: String {
        String(format: "%@ · usage 0x%04X · value %ld", usagePageName, usage, value)
    }

    var isButton: Bool { usagePage == 0x09 }
}

/// Reads raw HID reports from the CITLLA receiver. This requires Input
/// Monitoring and is only used by the diagnostics window; remapping itself
/// works through the CGEventTap and only needs Accessibility.
@MainActor
final class HIDMonitor: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var devices: [HIDDeviceInfo] = []
    @Published private(set) var events: [HIDEventEntry] = []
    @Published private(set) var errorMessage: String?

    private var manager: IOHIDManager?
    private let logger = Logger(subsystem: "com.ericng.citillae510", category: "hid")

    private static let maximumEvents = 250

    func start() {
        guard manager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [kIOHIDVendorIDKey: 0x1EA7, kIOHIDProductIDKey: 0x66],
            [kIOHIDVendorIDKey: 0x1EA7]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, citllaHIDDeviceAdded, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, citllaHIDDeviceRemoved, context)
        IOHIDManagerRegisterInputValueCallback(manager, citllaHIDValueReceived, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            errorMessage = String(
                format: "Could not open the mouse (0x%08X). Grant Input Monitoring to Citlla E510, then try again.",
                result
            )
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            logger.error("IOHIDManagerOpen failed: \(result, privacy: .public)")
            return
        }

        self.manager = manager
        isRunning = true
        errorMessage = nil
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        isRunning = false
        devices.removeAll()
    }

    func clearEvents() {
        events.removeAll()
    }

    fileprivate func upsertDevice(_ info: HIDDeviceInfo) {
        if !devices.contains(where: { $0.id == info.id }) {
            devices.append(info)
        }
    }

    fileprivate func removeDevice(id: UInt64) {
        devices.removeAll(where: { $0.id == id })
    }

    fileprivate func appendEvent(device: String, usagePage: Int, usage: Int, value: Int) {
        events.append(HIDEventEntry(
            device: device,
            usagePage: usagePage,
            usage: usage,
            value: value
        ))
        if events.count > Self.maximumEvents {
            events.removeFirst(events.count - Self.maximumEvents)
        }
    }
}

private func citllaHIDDeviceAdded(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ device: IOHIDDevice
) {
    guard let context else { return }
    let info = HIDDeviceInfo(
        id: UInt64(CFHash(device)),
        name: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown device",
        vendorID: IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0,
        productID: IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0,
        usagePage: IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0,
        usage: IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    )
    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.upsertDevice(info)
    }
}

private func citllaHIDDeviceRemoved(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ device: IOHIDDevice
) {
    guard let context else { return }
    let id = UInt64(CFHash(device))
    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.removeDevice(id: id)
    }
}

private func citllaHIDValueReceived(
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

    // Ignore pointer movement; it drowns out everything else.
    if page == 0x01 && (usage == 0x30 || usage == 0x31) { return }
    guard page == 0x01 || page == 0x09 || page == 0x0C || page == 0xFFB5 else { return }

    let device = IOHIDElementGetDevice(element)
    let deviceName = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Mouse"

    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.appendEvent(device: deviceName, usagePage: page, usage: usage, value: integerValue)
    }
}
