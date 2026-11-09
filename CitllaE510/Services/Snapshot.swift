import AppKit
import SwiftUI

/// Snapshots one of the app's own windows to a PNG.
///
/// The app is a menu bar utility with no Dock icon, and this machine does not
/// hand out screen-recording permission, so there is no other way to look at a
/// window from a script. Run it from the built app:
///
///     CitllaE510.app/Contents/MacOS/CitllaE510 --snapshot ~/Desktop/settings.png [--tab mouse|buttons|permissions|about] [--scale 2]
///     CitllaE510.app/Contents/MacOS/CitllaE510 --snapshot ~/Desktop/tester.png --window tester [--scale 2]
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
            let scale = max(1, Double(value(of: "--scale", in: args) ?? "1") ?? 1)
            guard let rep = bitmap(for: view, scale: scale) else {
                print("no bitmap")
                exit(4)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                print("no png")
                exit(5)
            }
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) view=\(Int(view.bounds.width))x\(Int(view.bounds.height)) pixels=\(rep.pixelsWide)x\(rep.pixelsHigh) window=\(Int(window.frame.width))x\(Int(window.frame.height))")
            exit(0)
        }
        return true
    }

    /// A bitmap for `view`, at `scale` device pixels per point.
    ///
    /// `bitmapImageRepForCachingDisplay` follows the window's backing scale,
    /// which is 1x for a window that never went on screen. A manual rep whose
    /// `size` is smaller than its pixel dimensions gives a 2x render instead.
    private static func bitmap(for view: NSView, scale: Double) -> NSBitmapImageRep? {
        guard scale > 1 else { return view.bitmapImageRepForCachingDisplay(in: view.bounds) }
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        return rep
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
