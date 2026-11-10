import Foundation

/// Who started a sequence, so a second press of the same control can cancel the
/// run that is already in flight.
///
/// A sequence takes up to three seconds, which is long enough for the user to
/// press the button again. The expected behaviour is "restart", not "queue", so
/// the runner keys its in-flight task by owner.
enum MacroOwner: Hashable, Sendable {
    /// A physical mouse button, 1-based like `ButtonBinding.button`.
    case button(Int)
    /// A keyboard or consumer key the mouse sends, by `ShortcutBinding.id`.
    case shortcut(String)
    /// One-shot probes (`--perform`, `--post-shortcut`) and tests.
    case other(String)
}
