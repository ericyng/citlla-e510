import AppKit
import CoreGraphics
import Foundation

/// `CitllaE510.app/Contents/MacOS/CitllaE510 --status` prints (and writes to
/// `~/Library/Application Support/CitllaE510/status.txt`) what the process can
/// actually do, then exits. Useful because an event tap silently does nothing
/// when Accessibility access is missing or has gone stale after a rebuild.
enum StatusProbe {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--status") else { return }

        let report = [
            "date: \(ISO8601DateFormatter().string(from: Date()))",
            "bundleID: \(Bundle.main.bundleIdentifier ?? "unknown")",
            "bundlePath: \(Bundle.main.bundlePath)",
            "accessibilityTrusted: \(AXIsProcessTrusted())",
            "inputMonitoring: \(PermissionManager.inputMonitoringStatusText)",
            "eventTapCreatable: \(canCreateEventTap())",
            "battery: \(MouseBattery.reading(from: MouseBattery.connectedDevices()).summaryText)"
        ].joined(separator: "\n")

        print(report)
        if let directory = ConfigStore.supportDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? Data(report.utf8).write(to: directory.appendingPathComponent("status.txt"))
        }

        exit(0)
    }

    private static func canCreateEventTap() -> Bool {
        let mask = CGEventMask(1) << CGEventMask(CGEventType.otherMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        CFMachPortInvalidate(tap)
        return true
    }
}
