import Foundation
import os

/// Runs a sequence of steps off the event-tap thread.
///
/// The tap callback must never sleep. Posting events is cheap, but waiting is
/// not: a tap that blocks for roughly half a second gets disabled by the system,
/// which silently stops every remapped control. So a sequence is started here
/// and the tap returns immediately.
///
/// Contract for the core-actions track:
///
/// - One run per owner. Pressing the control again cancels the run in flight and
///   starts the new one; runs do not queue.
/// - Steps fire in order, each waiting its own `clampedDelay` first.
/// - A cancelled run releases any modifiers it had pressed. No run may leave ⌘,
///   ⌥, ⌃ or ⇧ held down.
/// - Posted events keep `EventMarker`, so the app's own tap ignores them.
/// - Total time is capped by `SequenceLimits` and the run stops early if it
///   would exceed the cap.
@MainActor
enum MacroRunner {
    private static let logger = Logger(subsystem: "com.ericng.citillae510", category: "actions")

    /// Cancels any run in flight for `owner`, then runs `steps` asynchronously.
    ///
    /// `onStep` is called on the main actor immediately before step `index`
    /// fires, so the tester can highlight progress. It is not called for steps
    /// dropped by the limits.
    static func run(
        _ steps: [ActionStep],
        owner: MacroOwner,
        onStep: (@MainActor (Int) -> Void)? = nil
    ) {
        // TODO(core-actions): cancel + task scheduling + per-step wait.
        logger.debug("Sequence not implemented yet: \(steps.count) step(s) for \(String(describing: owner), privacy: .public)")
        _ = onStep
    }

    /// Cancels the run for `owner`, releasing anything it held.
    static func cancel(owner: MacroOwner) {
        // TODO(core-actions): cancel the stored task.
        _ = owner
    }

    /// Cancels every run. Called when remapping is switched off and at quit.
    static func cancelAll() {
        // TODO(core-actions): cancel every stored task.
    }
}
