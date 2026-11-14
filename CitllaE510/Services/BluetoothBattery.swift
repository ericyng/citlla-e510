import Foundation

/// Reads the battery levels of the Mac's connected Bluetooth devices.
///
/// macOS does not publish a third-party Bluetooth mouse's level into the
/// IORegistry. Apple-made accessories get an
/// `AppleDeviceManagementHIDEventService` node with a `BatteryPercent`, but the
/// E510 reports its level only through the Bluetooth stack's GATT Battery
/// Service, and that value never reaches the registry. The one supported,
/// read-only way to see it is `system_profiler`, which prints the same number
/// the Bluetooth menu shows. It needs no permission and never opens the device,
/// so it is safe to run beside remapping.
enum BluetoothBattery {
    /// The connected Bluetooth devices macOS reports, with their levels.
    ///
    /// Returns an empty list on any failure, so a missing or wedged
    /// `system_profiler` degrades to "no Bluetooth level" instead of an error.
    static func connectedDevices() -> [HIDBatteryDevice] {
        guard let data = systemProfilerJSON() else { return [] }
        return devices(fromJSON: data)
    }

    /// The pure part: turn `system_profiler -json SPBluetoothDataType` into the
    /// battery-bearing devices the resolver understands.
    ///
    /// Only `device_connected` is read, and only entries with a main battery
    /// level. A connected device with no level is not something the app can
    /// show, and the disconnected list is stale by definition.
    static func devices(fromJSON data: Data) -> [HIDBatteryDevice] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var devices: [HIDBatteryDevice] = []
        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let properties = value as? [String: Any] else { continue }
                    guard let percent = percent(from: properties["device_batteryLevelMain"]) else {
                        continue
                    }
                    devices.append(HIDBatteryDevice(
                        name: name,
                        vendorID: hexadecimalID(properties["device_vendorID"]) ?? 0,
                        productID: hexadecimalID(properties["device_productID"]) ?? 0,
                        transport: "Bluetooth",
                        batteryPercent: percent
                    ))
                }
            }
        }
        return devices
    }

    /// `"100%"` -> `100`. Anything without digits is treated as no level.
    private static func percent(from value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        let digits = text.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    /// `"0x32C2"` -> `12994`. Stops at the first non-hex character, so a
    /// trailing annotation like `"0x004C (Apple)"` still parses.
    private static func hexadecimalID(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        let body = text.hasPrefix("0x") || text.hasPrefix("0X")
            ? text.dropFirst(2)
            : Substring(text)
        let digits = body.prefix(while: \.isHexDigit)
        return digits.isEmpty ? nil : Int(digits, radix: 16)
    }

    /// Runs `system_profiler -json SPBluetoothDataType` and returns its stdout.
    private static func systemProfilerJSON() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read to EOF before waiting: a full pipe buffer would deadlock the
        // child if it blocked writing while we blocked in `waitUntilExit`.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }
}
