import Foundation
import IOKit
import os

/// One HID device that macOS is willing to talk about, reduced to the fields
/// the battery resolver needs.
///
/// The connection facts — the name and the transport — come from the
/// `AppleUserHIDEventService` node in the IORegistry. The level does not: for a
/// third-party mouse the IORegistry node carries no `BatteryPercent`, and the
/// value is filled in from the Bluetooth stack instead (see
/// `BluetoothBattery`). The receiver's interfaces never carry a level, which is
/// why a dongle connection resolves to `.notReported` (see
/// `MouseBattery.reading`).
struct HIDBatteryDevice: Identifiable, Hashable, Sendable {
    let name: String
    let vendorID: Int
    let productID: Int
    /// The `Transport` value: `USB` for the 2.4 GHz receiver,
    /// `Bluetooth Low Energy` (or `Bluetooth`) for a paired mouse.
    let transport: String
    /// The level macOS reports, if any. Its absence is meaningful: the device
    /// is connected but publishes no battery level. The merge in
    /// `MouseBattery.mergedDevices` fills this in from the Bluetooth stack.
    var batteryPercent: Int?

    var id: String {
        String(format: "%04X:%04X:%@:%@", vendorID, productID, transport, name)
    }

    var isBluetooth: Bool {
        transport.lowercased().contains("bluetooth")
    }

    var source: MouseBatterySource {
        isBluetooth ? .bluetooth : .receiver
    }

    var idDescription: String {
        String(format: "VID 0x%04X · PID 0x%04X", vendorID, productID)
    }
}

/// Where a reading came from.
enum MouseBatterySource: String, Sendable, Equatable {
    case bluetooth
    case receiver

    var label: String {
        switch self {
        case .bluetooth: "Bluetooth"
        case .receiver: "2.4 GHz receiver"
        }
    }

    var shortLabel: String {
        switch self {
        case .bluetooth: "Bluetooth"
        case .receiver: "2.4 GHz"
        }
    }
}

/// What the app knows about the mouse's battery right now.
enum MouseBatteryKind: Sendable, Equatable {
    /// Nothing has been read yet (the monitor has not run).
    case unknown
    /// The app looked and found neither the dongle nor a Bluetooth node.
    case unreachable
    /// The mouse is connected, but this connection publishes no level.
    case notReported
    /// A percentage, already clamped to 0…100.
    case reported(Int)
}

/// A snapshot of the mouse's battery state, with the strings the UI needs.
///
/// Kept free of SwiftUI so the resolver can be unit-tested; the views pick a
/// colour from `isLow` / `isCritical`.
struct MouseBatteryReading: Sendable, Equatable {
    var kind: MouseBatteryKind = .unknown
    var source: MouseBatterySource?
    var deviceName: String?
    /// When this reading was taken, so the UI can say how fresh it is.
    var updated: Date?

    /// The state before the first read.
    static let notYetRead = MouseBatteryReading()

    var percent: Int? {
        if case .reported(let percent) = kind { percent } else { nil }
    }

    var isReported: Bool { percent != nil }

    var isConnected: Bool {
        switch kind {
        case .unknown, .unreachable: false
        case .notReported, .reported: true
        }
    }

    var isLow: Bool {
        guard let percent else { return false }
        return percent <= MouseBattery.lowThreshold
    }

    var isCritical: Bool {
        guard let percent else { return false }
        return percent <= MouseBattery.criticalThreshold
    }

    /// The short value the menu bar and the Device row show.
    var valueText: String {
        switch kind {
        case .unknown: "Not read yet"
        case .unreachable: "Not connected"
        case .notReported: "Not reported"
        case .reported(let percent): "\(percent)%"
        }
    }

    /// One line for the menu bar menu, where there is no room for detail.
    var summaryText: String {
        switch kind {
        case .unknown:
            return "Battery · not read yet"
        case .unreachable:
            return "Battery · mouse not connected"
        case .notReported:
            return "Battery · not reported over \(source?.shortLabel ?? "this connection")"
        case .reported(let percent):
            if let source {
                return "Battery · \(percent)% (\(source.label))"
            }
            return "Battery · \(percent)%"
        }
    }

    /// Why the row says what it says. The honest answer matters here: a dongle
    /// connection cannot show a level, and the UI must not look broken.
    var explanation: String {
        switch kind {
        case .unknown:
            return "The level is read from macOS when the app starts."
        case .unreachable:
            return "Connect the mouse over Bluetooth, or plug in its 2.4 GHz receiver."
        case .notReported:
            switch source {
            case .bluetooth:
                return "This Bluetooth connection does not publish a battery level yet. It appears once macOS reads one."
            case .receiver, nil:
                return "The 2.4 GHz receiver does not send a battery level. Switch the mouse to Bluetooth to see it."
            }
        case .reported:
            switch source {
            case .bluetooth:
                return "Read from the mouse's Bluetooth connection."
            case .receiver:
                return "Read from the 2.4 GHz receiver."
            case nil:
                return "Read from the connected mouse."
            }
        }
    }

    /// A battery symbol for a reported level, and a neutral one otherwise, so
    /// "not reported" never looks like an empty battery.
    var symbolName: String {
        switch kind {
        case .unknown: "ellipsis.circle"
        case .unreachable: "computermouse"
        case .notReported: "bolt.horizontal.circle"
        case .reported(let percent):
            switch percent {
            case ...10: "battery.0percent"
            case ...25: "battery.25percent"
            case ...50: "battery.50percent"
            case ...75: "battery.75percent"
            default: "battery.100percent"
            }
        }
    }

    /// What VoiceOver reads for the menu bar item.
    var accessibilityText: String {
        switch kind {
        case .unknown, .unreachable:
            return "Citlla E510"
        case .notReported:
            return "Citlla E510, battery not reported"
        case .reported(let percent):
            return "Citlla E510, battery \(percent) percent"
        }
    }
}

/// Resolves the mouse's battery level from the HID devices macOS reports.
enum MouseBattery {
    /// At or below this percentage the UI warns.
    static let lowThreshold = 20
    /// At or below this percentage the UI warns in red.
    static let criticalThreshold = 10

    /// The devices the app cares about, out of everything in the IORegistry.
    ///
    /// Matching stays on the exact vendor/product pairs in
    /// `MouseReceiver.known`: the receiver chip's vendor ID is generic, so a
    /// vendor-only match would pick up other devices.
    static func isMouseDevice(_ device: HIDBatteryDevice) -> Bool {
        MouseReceiver.receiver(vendorID: device.vendorID, productID: device.productID) != nil
    }

    /// The pure part: decide what to show from the devices macOS lists.
    ///
    /// Precedence, highest first:
    /// 1. any device that actually reports a percentage (Bluetooth first),
    /// 2. a receiver on USB, because a plugged-in dongle is a stronger signal
    ///    than a remembered Bluetooth node that macOS keeps registered while
    ///    the mouse is on 2.4 GHz,
    /// 3. any other mouse node, which is Bluetooth and reports nothing.
    static func reading(from devices: [HIDBatteryDevice], now: Date = Date()) -> MouseBatteryReading {
        let devices = devices.filter(isMouseDevice)
        guard !devices.isEmpty else {
            return MouseBatteryReading(kind: .unreachable, updated: now)
        }

        let reporting = devices
            .filter { $0.batteryPercent != nil }
            .sorted { lhs, rhs in
                if lhs.isBluetooth != rhs.isBluetooth { return lhs.isBluetooth }
                return lhs.name < rhs.name
            }
        if let device = reporting.first, let percent = device.batteryPercent {
            return MouseBatteryReading(
                kind: .reported(clamp(percent)),
                source: device.source,
                deviceName: device.name,
                updated: now
            )
        }

        if let device = devices.first(where: { $0.source == .receiver }) {
            return MouseBatteryReading(
                kind: .notReported,
                source: .receiver,
                deviceName: device.name,
                updated: now
            )
        }

        let device = devices[0]
        return MouseBatteryReading(
            kind: .notReported,
            source: device.source,
            deviceName: device.name,
            updated: now
        )
    }

    /// Keeps a bad value from a misbehaving device out of the UI.
    static func clamp(_ percent: Int) -> Int {
        min(100, max(0, percent))
    }

    /// Everything the app knows about the mouse's connection right now.
    ///
    /// The IORegistry says what is connected and over which transport; the
    /// Bluetooth stack is the only place a third-party mouse's level appears.
    static func connectedDevices() -> [HIDBatteryDevice] {
        mergedDevices(
            registry: registryDevices(),
            bluetooth: BluetoothBattery.connectedDevices()
        )
    }

    /// Combines the two sources into the list the resolver sees.
    ///
    /// A Bluetooth device found in both is one device: the registry supplies
    /// the transport and the stack supplies the level. A Bluetooth mouse that
    /// the registry did not list is added as-is, and any other Bluetooth device
    /// is dropped.
    static func mergedDevices(
        registry: [HIDBatteryDevice],
        bluetooth: [HIDBatteryDevice]
    ) -> [HIDBatteryDevice] {
        var devices = registry
        for device in bluetooth where isMouseDevice(device) {
            if let index = devices.firstIndex(where: {
                $0.isBluetooth && $0.vendorID == device.vendorID && $0.productID == device.productID
            }) {
                devices[index].batteryPercent = device.batteryPercent ?? devices[index].batteryPercent
            } else {
                devices.append(device)
            }
        }
        return devices
    }

    /// Reads every `AppleUserHIDEventService` node and keeps the mouse ones.
    ///
    /// This gives the connection's transport and name but, on this hardware, no
    /// level: the E510's node has no `BatteryPercent`. Reading the IORegistry
    /// needs no permission and no entitlement, and it does not open the device,
    /// so it is safe to do while remapping runs.
    private static func registryDevices() -> [HIDBatteryDevice] {
        guard let matching = IOServiceMatching("AppleUserHIDEventService") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var seen = Set<String>()
        var devices: [HIDBatteryDevice] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            let vendorID = integerProperty(entry, "VendorID") ?? 0
            let productID = integerProperty(entry, "ProductID") ?? 0
            guard MouseReceiver.receiver(vendorID: vendorID, productID: productID) != nil else {
                continue
            }
            // One node per HID interface: the E510's receiver exposes a mouse
            // and a keyboard interface with identical IDs. They share a reading,
            // so keep the first.
            let transport = stringProperty(entry, "Transport") ?? "Unknown"
            let name = stringProperty(entry, "Product")
                ?? MouseReceiver.receiver(vendorID: vendorID, productID: productID)?.name
                ?? "Citlla E510"
            let device = HIDBatteryDevice(
                name: name,
                vendorID: vendorID,
                productID: productID,
                transport: transport,
                batteryPercent: integerProperty(entry, "BatteryPercent")
            )
            if seen.insert(device.id).inserted {
                devices.append(device)
            }
        }
        return devices
    }

    private static func integerProperty(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }
        return value as? String
    }
}

/// Polls for the mouse's battery level.
///
/// There is no notification for this, and the level changes slowly, so a
/// minute is plenty. The read needs no permission and no device access, so
/// polling never disturbs the mouse or the event tap.
@MainActor
final class MouseBatteryMonitor: ObservableObject {
    @Published private(set) var reading: MouseBatteryReading = .notYetRead

    /// How often the level is re-read.
    static let pollInterval: Duration = .seconds(60)

    private var pollTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.ericng.citillae510", category: "battery")

    /// Reads once now and keeps reading while the app runs. Safe to call
    /// repeatedly; only one poll loop exists at a time.
    func start() {
        refresh()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: MouseBatteryMonitor.pollInterval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Re-reads the registry and publishes the result.
    func refresh() {
        let devices = MouseBattery.connectedDevices()
        reading = MouseBattery.reading(from: devices)
        logger.debug("battery: \(self.reading.summaryText, privacy: .public) from \(devices.count) device(s)")
    }
}
