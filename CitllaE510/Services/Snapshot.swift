import AppKit
import SwiftUI

/// Snapshots the app's main window to a PNG.
///
/// The app is a menu bar utility with no Dock icon, and this machine does not
/// hand out screen-recording permission, so there is no other way to look at a
/// window from a script. Run it from the built app:
///
///     CitllaE510.app/Contents/MacOS/CitllaE510 --snapshot ~/Desktop/main.png --window main --section overview [--scale 2]
///     CitllaE510.app/Contents/MacOS/CitllaE510 --snapshot ~/Desktop/settings.png [--tab mouse|buttons|permissions|about] [--scale 2]
///     CitllaE510.app/Contents/MacOS/CitllaE510 --snapshot ~/Desktop/tester.png --window tester [--scale 2]
///
/// `--window main` opens the main window on `--section` (any id from
/// `MainSection.available`; `overview` by default). `--window tester` is the old
/// form and snapshots the main window's Advanced / Button Tester pane. The
/// view is drawn with `cacheDisplay`, so it works without any permission.
///
/// The real window is a `NavigationSplitView`. Its sidebar is a Liquid Glass
/// portal on macOS 26+, which an offscreen `cacheDisplay` cannot see, so the
/// snapshot renders `MainWindowSnapshotView` instead: the same `MainSidebar`
/// and `MainSectionContent` in an ordinary hosting window. Every section is
/// still the real view, at the real window size.
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
        let sectionName = value(of: "--section", in: args)
        let scale = max(1, Double(value(of: "--scale", in: args) ?? "1") ?? 1)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))

            // The documented snapshots are light-mode renders; force the same
            // appearance so a dark-mode machine does not produce white text on
            // a white background.
            NSApp.appearance = NSAppearance(named: .aqua)

            let state = MainWindowState()
            switch windowName {
            case "tester":
                state.selection = .advanced
                state.advancedPane = .tester
            case "main":
                state.selection = section(named: sectionName)
            default:
                state.selection = SettingsTab(name: tab).mainSection
            }

            let root = MainWindowSnapshotView()
                .environmentObject(AppModel.shared.config)
                .environmentObject(AppModel.shared.eventTap)
                .environmentObject(AppModel.shared.loginItem)
                .environmentObject(AppModel.shared.activeApp)
                .environmentObject(state)

            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Citlla E510"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 1080, height: 720))
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)

            // Let the section lay out, the tester start, and List/TabView draw.
            try? await Task.sleep(for: .milliseconds(1600))

            guard let view = window.contentView else {
                print("no window content to snapshot")
                exit(3)
            }
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()

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
            print("wrote \(path) section=\(state.selection.rawValue) view=\(Int(view.bounds.width))x\(Int(view.bounds.height)) pixels=\(rep.pixelsWide)x\(rep.pixelsHigh)")
            exit(0)
        }
        return true
    }

    private static func section(named name: String?) -> MainSection {
        guard let name, let section = MainSection(rawValue: name), MainSection.available.contains(section) else {
            return .overview
        }
        return section
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
