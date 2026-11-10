import CoreGraphics
import Foundation

/// What the tap should do with one scroll event.
enum ScrollOutcome: Equatable {
    /// The event was not worth touching and is handed on unchanged.
    case passThrough
    /// The same event object had its deltas inverted in place.
    case rewritten
    /// A side-wheel gesture. `fire` is true for the first event of the
    /// gesture; every event of the gesture is swallowed so a bound tilt does
    /// not also scroll sideways.
    case tilt(TiltDirection, fire: Bool)
}

/// Scroll direction inversion and side-wheel actions.
///
/// Everything here works on the event the tap was handed and returns the same
/// event. Nothing is re-posted: a re-post would either need the marker to be
/// ignored or would loop through the tap, and it would drop the phase,
/// momentum and timestamp the system put on the event. Writing the six delta
/// fields covers line-based wheels, pixel-precise wheels and the fixed-point
/// deltas apps use for smooth scrolling, all in the same pass.
struct ScrollController: Sendable {
    /// How long the side wheel must stay quiet before a new flick triggers
    /// again. One flick sends a burst of events over 50-150 ms; without the
    /// window every event in the burst would fire the action.
    static let tiltCooldown: TimeInterval = 0.25

    /// When each direction was last seen. Updated on every event of a gesture,
    /// so a held tilt cannot retrigger every 250 ms.
    private var lastTiltEvent: [TiltDirection: TimeInterval] = [:]

    /// The outcome for one scroll event. `time` exists so tests can drive the
    /// gesture window; the tap passes nil and the event's own timestamp is used.
    mutating func handle(
        _ event: CGEvent,
        settings: ScrollSettings,
        at time: TimeInterval? = nil
    ) -> ScrollOutcome {
        // Events the app posted itself must never be touched, even if a future
        // feature re-posts one instead of rewriting it in place.
        guard event.getIntegerValueField(.eventSourceUserData) != EventMarker.value else {
            return .passThrough
        }

        if let direction = Self.tiltDirection(of: event), settings.action(for: direction).isBound {
            let now = time ?? Self.timestamp(of: event)
            let isNewGesture = lastTiltEvent[direction].map { now - $0 >= Self.tiltCooldown } ?? true
            lastTiltEvent[direction] = now
            return .tilt(direction, fire: isNewGesture)
        }

        guard settings.invertVertical || settings.invertHorizontal else {
            return .passThrough
        }

        var didChange = false
        if settings.invertVertical {
            didChange = Self.flip(
                event,
                line: .scrollWheelEventDeltaAxis1,
                point: .scrollWheelEventPointDeltaAxis1,
                fixedPoint: .scrollWheelEventFixedPtDeltaAxis1
            ) || didChange
        }
        if settings.invertHorizontal {
            didChange = Self.flip(
                event,
                line: .scrollWheelEventDeltaAxis2,
                point: .scrollWheelEventPointDeltaAxis2,
                fixedPoint: .scrollWheelEventFixedPtDeltaAxis2
            ) || didChange
        }
        return didChange ? .rewritten : .passThrough
    }

    // MARK: - Tilt detection

    /// The direction of a side-wheel event, or nil when the event is an honest
    /// horizontal scroll.
    ///
    /// A trackpad or Magic Mouse pan is continuous and carries phase and
    /// momentum information, so "not continuous, no phase, no momentum" is what
    /// separates it from the side wheel, which macOS delivers as a plain
    /// line-based wheel on the horizontal axis. The horizontal delta must also
    /// be at least as large as any vertical one, so a diagonal scroll from a
    /// four-way wheel is not mistaken for a tilt. A shift is treated as an
    /// honest horizontal scroll too, in case a driver has already turned
    /// shift+wheel into axis 2 before the tap sees it.
    static func tiltDirection(of event: CGEvent) -> TiltDirection? {
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
              event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
              !event.flags.contains(.maskShift) else {
            return nil
        }
        let vertical = delta(of: event, axis: 1)
        let horizontal = delta(of: event, axis: 2)
        guard horizontal != 0, abs(horizontal) >= abs(vertical) else { return nil }
        return TiltDirection.direction(forHorizontalDelta: horizontal)
    }

    /// The delta on one axis, whichever of the three fields carries it.
    static func delta(of event: CGEvent, axis: Int) -> Int64 {
        let line: CGEventField = axis == 1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2
        let point: CGEventField = axis == 1 ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2
        let fixed: CGEventField = axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2

        let lineDelta = event.getIntegerValueField(line)
        if lineDelta != 0 { return lineDelta }
        let pointDelta = event.getIntegerValueField(point)
        if pointDelta != 0 { return pointDelta }
        return event.getIntegerValueField(fixed)
    }

    // MARK: - Inversion

    /// Negates the three fields that describe one axis. Returns false when the
    /// axis carried no delta at all, so an event that needed no change can be
    /// handed on untouched.
    ///
    /// The line delta is whole wheel clicks, the point delta whole points, and
    /// the fixed-point delta the same value as 16.16 points. All three are
    /// negated so a line-based app and a pixel-precise one see the same
    /// direction and the same magnitude.
    ///
    /// Order matters: writing the line delta makes `CGEvent` rebuild the point
    /// and fixed-point fields from it, which rounds a smooth fractional delta
    /// to a whole line. Both are therefore captured first and written back
    /// afterwards. Writing either of those leaves the line delta alone.
    @discardableResult
    private static func flip(
        _ event: CGEvent,
        line: CGEventField,
        point: CGEventField,
        fixedPoint: CGEventField
    ) -> Bool {
        let lineDelta = event.getIntegerValueField(line)
        let pointDelta = event.getIntegerValueField(point)
        let fixedDelta = event.getIntegerValueField(fixedPoint)
        guard lineDelta != 0 || pointDelta != 0 || fixedDelta != 0 else { return false }

        event.setIntegerValueField(line, value: -lineDelta)
        event.setIntegerValueField(fixedPoint, value: -fixedDelta)
        event.setIntegerValueField(point, value: -pointDelta)
        return true
    }

    // MARK: - Time

    /// `CGEvent` timestamps are nanoseconds since boot.
    private static func timestamp(of event: CGEvent) -> TimeInterval {
        let nanos = event.timestamp
        guard nanos > 0 else { return ProcessInfo.processInfo.systemUptime }
        return TimeInterval(nanos) / 1_000_000_000
    }
}
