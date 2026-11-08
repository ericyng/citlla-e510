import AppKit
@preconcurrency import ApplicationServices
import Foundation
@preconcurrency import IOKit.hid

enum PermissionManager {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var inputMonitoringStatus: IOHIDAccessType {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    }

    static var hasInputMonitoring: Bool {
        inputMonitoringStatus == kIOHIDAccessTypeGranted
    }

    static var inputMonitoringStatusText: String {
        switch inputMonitoringStatus.rawValue {
        case kIOHIDAccessTypeGranted.rawValue: "Granted"
        case kIOHIDAccessTypeDenied.rawValue: "Denied"
        default: "Not requested"
        }
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
