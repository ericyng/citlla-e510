import AppKit
import Foundation
import os

/// One step the runner will fire, with the delay it honours first and its index
/// in the normalised step list. `onStep` reports that index.
struct ScheduledActionStep: Equatable, Sendable {
    let index: Int
    let step: ActionStep
    let delayMilliseconds: Int
}

/// Runs a sequence of steps off the event-tap thread.
///
/// The tap callback must never sleep. Posting events is cheap, but waiting is
/// not: a tap that blocks for roughly half a second gets disabled by the system,
/// which silently stops every remapped control. So a sequence is started here
/// and the tap returns immediately.
///
/// Contract:
///
/// - One run per owner. Pressing the control again cancels the run in flight and
///   starts the new one; runs do not queue.
/// - Steps fire in order, each waiting its own `clampedDelay` first.
/// - A step is atomic: modifiers go down, the key or click is posted, and the
///   modifiers come up in a `defer` inside `ActionExecutor`. Nothing here ever
///   waits between pressing and releasing a modifier, so a cancellation - which
///   can only land on an `await` - cannot leave ⌘, ⌥, ⌃ or ⇧ held down.
/// - Posted events keep `EventMarker`, so the app's own tap ignores them.
/// - Total time is capped by `SequenceLimits` and the run stops early if it
///   would exceed the cap.
@MainActor
enum MacroRunner {
    private static let logger = Logger(subsystem: "com.ericng.citillae510", category: "actions")

    /// One in-flight run. The id lets a finishing run clear its own entry
    /// without stomping on a newer run that replaced it in the meantime.
    private struct Run {
        let id: UUID
        let task: Task<Void, Never>
    }

    private static var runs: [MacroOwner: Run] = [:]
    private static var terminationObserver: NSObjectProtocol?

    // MARK: - Running

    /// Cancels any run in flight for `owner`, then runs `steps` asynchronously.
    ///
    /// `onStep` is called on the main actor immediately before step `index`
    /// fires, so the tester can highlight progress. It is not called for steps
    /// dropped by the limits.
    static func run(
        _ steps: [ActionStep],
        owner: MacroOwner,
        onStep: (@MainActor (Int) -> Void)? = nil,
        sink: any EventSink = ActionExecutor.sink
    ) {
        cancel(owner: owner)

        let normalised = steps.normalized()
        logDrops(from: steps, to: normalised)

        let scheduled = plan(for: normalised)
        guard !scheduled.isEmpty else {
            logger.debug("Sequence for \(String(describing: owner), privacy: .public) has nothing to run")
            return
        }
        if scheduled.count < normalised.count {
            logger.notice(
                "Sequence stopped at \(scheduled.count) of \(normalised.count) step(s): \(SequenceLimits.maxTotalMilliseconds) ms cap"
            )
        }

        installTerminationObserverIfNeeded()

        let id = UUID()
        let task = Task { @MainActor in
            for entry in scheduled {
                if Task.isCancelled { break }
                if entry.delayMilliseconds > 0 {
                    do {
                        try await Task.sleep(for: .milliseconds(entry.delayMilliseconds))
                    } catch {
                        break // Cancelled while waiting; nothing was pressed.
                    }
                }
                if Task.isCancelled { break }
                onStep?(entry.index)
                ActionExecutor.performStep(entry.step, sink: sink)
            }
            finish(owner: owner, id: id)
        }
        runs[owner] = Run(id: id, task: task)
    }

    /// Cancels the run for `owner`. The task clears its own entry when it stops.
    static func cancel(owner: MacroOwner) {
        runs.removeValue(forKey: owner)?.task.cancel()
    }

    /// Cancels every run. Called at quit, and available for the points that
    /// switch remapping off.
    static func cancelAll() {
        let inFlight = runs.values
        runs.removeAll()
        for run in inFlight {
            run.task.cancel()
        }
    }

    // MARK: - Scheduling

    /// Normalises `steps` and trims them to the total time budget.
    ///
    /// Pure so the caps can be tested without waiting three seconds: a sequence
    /// whose waits add up to more than `maxTotalMilliseconds` keeps the prefix
    /// that fits. Steps after the budget are dropped, because firing them late
    /// would be the same as ignoring the cap.
    nonisolated static func plan(for steps: [ActionStep]) -> [ScheduledActionStep] {
        var remaining = SequenceLimits.maxTotalMilliseconds
        var scheduled: [ScheduledActionStep] = []
        for (index, step) in steps.normalized().enumerated() {
            let delay = step.clampedDelay
            guard delay <= remaining else { break }
            scheduled.append(ScheduledActionStep(index: index, step: step, delayMilliseconds: delay))
            remaining -= delay
        }
        return scheduled
    }

    /// Why a config can hand us steps the editor never would.
    ///
    /// `config.json` is editable by hand, so a step can name `.none` or even
    /// `.sequence` (a nested run, which the runner refuses to recurse into).
    /// Logging the drops makes a misbehaving macro explainable instead of
    /// silently shorter.
    private static func logDrops(from original: [ActionStep], to normalised: [ActionStep]) {
        guard normalised.count != original.count else { return }

        let nested = original.contains { $0.kind == .sequence }
        let empty = original.contains { $0.kind == .none }
        logger.notice(
            "Sequence trimmed from \(original.count) to \(normalised.count) step(s); nested=\(nested) empty=\(empty) cap=\(SequenceLimits.maxSteps)"
        )
    }

    private static func finish(owner: MacroOwner, id: UUID) {
        guard runs[owner]?.id == id else { return }
        runs[owner] = nil
    }

    // MARK: - Quit

    /// Cancels every run when the app terminates.
    ///
    /// The executor releases modifiers around each step, so a run normally holds
    /// nothing between steps. This is the belt-and-braces path: the task is
    /// cancelled before the process goes away, so no step starts after quit.
    /// The observer is installed lazily on the first run, which keeps this file
    /// self-contained (the call sites in `AppDelegate` are owned elsewhere).
    private static func installTerminationObserverIfNeeded() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                cancelAll()
            }
        }
    }
}
