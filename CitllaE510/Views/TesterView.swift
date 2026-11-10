import AppKit
import SwiftUI

struct TesterView: View {
    @ObservedObject var tester: ButtonTester
    var actions: (MouseControl) -> [MouseAction] = { _ in [] }

    @State private var pulse: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let error = tester.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            content
            Divider()
            sequenceStrip
            Divider()
            log
        }
        .frame(minWidth: 860, minHeight: 600)
        .onReceive(tester.$hits) { hits in
            guard let newest = hits.max(by: { $0.value.last < $1.value.last })?.key else { return }
            pulse.insert(newest)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                pulse.remove(newest)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Button Tester")
                    .font(.largeTitle.bold())
                Text("Press every control on the mouse, click the wheel, and tilt the side wheel. Nothing is suppressed while this window is open — it only watches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(tester.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(tester.isRunning ? "Listening" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(tester.isRunning ? "Pause" : "Start") {
                tester.isRunning ? tester.stop() : tester.start()
            }
            Button("Clear") { tester.clear() }
            Button("Copy Report") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tester.report(), forType: .string)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 22) {
            MouseRenderPair(height: 210, spacing: 10, highlighted: pulse)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What each control sends")
                        .font(.headline)
                        .padding(.bottom, 2)
                    MouseControlLegend(
                        actions: actions,
                        detection: detection(for:),
                        highlighted: pulse
                    )
                    if let unmapped = tester.lastUnmapped {
                        Divider()
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Not on the diagram")
                                    .font(.callout.weight(.medium))
                                Text(unmapped)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func detection(for control: MouseControl) -> String? {
        guard let hit = tester.hits[control.number] else { return nil }
        var text = hit.detail
        if let button = hit.button {
            text = "Mouse button \(button)"
        }
        text += "  ×\(hit.count)"
        return text
    }

    // MARK: - Sequence progress

    /// Shows the step that is firing and, once it is done, "ran N steps".
    ///
    /// The tester mirrors the run on a silent sink (`ButtonTester`), so this
    /// never posts anything and never waits: the strip updates as the runner's
    /// `onStep` callbacks land on the main actor.
    private var sequenceStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .foregroundStyle(.secondary)

                if let progress = tester.sequenceProgress {
                    Text(progress.finished ? "Ran \(progress.total) steps" : "Running step \(progress.currentNumber ?? 1) of \(progress.total)")
                        .font(.callout.weight(.medium))
                    Text("· \(progress.label)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sequence")
                        .font(.callout.weight(.medium))
                    Text("· press a control bound to a Sequence to watch its steps. The tester mirrors the run and posts nothing itself.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            if let progress = tester.sequenceProgress {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(progress.steps.enumerated()), id: \.offset) { index, step in
                            stepChip(
                                number: index + 1,
                                delay: step.clampedDelay,
                                summary: step.summary,
                                active: progress.current == index
                            )
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: 22)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func stepChip(number: Int, delay: Int, summary: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text("\(number)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            if delay > 0 {
                Text("\(delay) ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(summary)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(active ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(active ? Color.accentColor : .clear)
        )
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Event log")
                    .font(.headline)
                Text("\(tester.events.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            if tester.events.isEmpty {
                Text("No events yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(tester.events.reversed()) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.timeFormatter.string(from: event.date))
                                    .foregroundStyle(.tertiary)
                                Text(event.category)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 62, alignment: .leading)
                                Text(event.summary)
                                Text(event.detail)
                                    .foregroundStyle(.tertiary)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
        }
        .frame(height: 150)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
