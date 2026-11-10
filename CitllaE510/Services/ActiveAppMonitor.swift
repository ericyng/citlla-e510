import AppKit
import Foundation

/// Caches the bundle identifier of the frontmost app so the event tap can do a
/// profile lookup on every event without asking `NSWorkspace`.
///
/// One instance is owned by `AppModel` and shared by the tap and the views.
/// `NSWorkspace.didActivateApplicationNotification` arrives on the main queue
/// for the observer below, so no polling timer and no XPC are involved.
@MainActor
final class ActiveAppMonitor: ObservableObject {
    /// The bundle identifier of the app that is frontmost now, or `nil` while
    /// there is no regular app in front (the desktop, a transient panel).
    @Published private(set) var frontmostBundleID: String?

    private var observer: NSObjectProtocol?

    init() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Starts observing app activations. Safe to call repeatedly; the observer
    /// is installed once and removed by `stop()`.
    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            // `queue: .main` delivers on the main thread, so this is the same
            // synchronous hand-off the event tap uses from its callback.
            MainActor.assumeIsolated {
                self?.frontmostBundleID = bundleID
            }
        }
    }

    /// Removes the observer. Safe to call when not started.
    func stop() {
        guard let observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
