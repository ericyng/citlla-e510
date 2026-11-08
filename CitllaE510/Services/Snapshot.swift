import AppKit
import SwiftUI

/// Snapshots one of the app's own windows to a PNG.
///
/// The app is a menu bar utility with no Dock icon, and this machine does not
/// hand out screen-recording permission, so there is no other way to look at a
/// window from a script. Run it from the built app:
///
///     CitllaE510.app/Contents/MacOS/CitllaE510 --snapshot ~/Desktop/settings.png [--tab mouse|buttons|permissions|about]
///     CitllaE510.app/Contents/MacOS/CitllaE510 --snapshot ~/Desktop/tester.png --window tester
///
/// The view is drawn with `cacheDisplay`, so it works without any permission.
@MainActor
enum Snapshot {
    /// Returns true when the app was launched to take a snapshot, so the normal
    /// launch path should be skipped.
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), flag + 1 < args.count else { return false }
        let path = args[flag + 1]
        let tab = value(of: "--tab", in: args) ?? "mouse"
        let windowName = value(of: "--window", in: args) ?? "settings"

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if windowName == "tester" {
                WindowManager.shared.showTester()
            } else {
                WindowManager.shared.showSettings(tab: SettingsTab(name: tab))
            }
            try? await Task.sleep(for: .milliseconds(1800))

            let windows = NSApp.windows.filter(\.isVisible)
            print("visible windows: \(windows.map(\.title))")
            guard let window = windows.first(where: { $0.title.contains(windowName == "tester" ? "Tester" : "Settings") }),
                  let view = window.contentView else {
                print("no window to snapshot")
                exit(3)
            }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                print("no bitmap")
                exit(4)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                print("no png")
                exit(5)
            }
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) view=\(Int(view.bounds.width))x\(Int(view.bounds.height)) window=\(Int(window.frame.width))x\(Int(window.frame.height))")
            exit(0)
        }
        return true
    }

    private static func value(of flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

extension SettingsTab {
    init(name: String) {
        switch name {
        case "buttons": self = .buttons
        case "permissions": self = .permissions
        case "about": self = .about
        default: self = .mouse
        }
    }
}
