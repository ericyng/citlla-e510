import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The step list for a `.sequence` action.
///
/// Every row is the same `ActionFieldsView` the top-level editor uses, so a step
/// can be a system action, a shortcut, a click (with chord modifiers), an app,
/// a URL or a command — exactly what a whole action can be, minus another
/// sequence. Delays are per step and are printed in firing order by the preview.
struct MacroEditorView: View {
    @Binding var steps: [ActionStep]

    /// The row being dragged, for the drop delegate. `nil` when nothing is.
    @State private var dragging: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview

            if steps.isEmpty {
                emptyState
            } else {
                stepList
            }

            footer
        }
    }

    // MARK: - Preview

    private var preview: some View {
        let total = SequencePreview.totalDelay(of: steps)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Sequence")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(SequencePreview.text(for: steps))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Buttons and the mouse map will show: \(MouseAction(kind: .sequence, steps: steps).summary)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if total > SequenceLimits.maxTotalMilliseconds {
                Label(
                    "Total waits are \(total) ms; the runner stops at \(SequenceLimits.maxTotalMilliseconds) ms, so the last steps will not fire.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No steps yet")
                .font(.callout.weight(.medium))
            Text("Add a step, or choose a preset from the top right.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.quaternary)
        )
    }

    // MARK: - Steps

    private var stepList: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Indices as identity is enough here: the list is short, and every
                // row binds `steps[index]`, so a move re-renders each row in place.
                ForEach(steps.indices, id: \.self) { index in
                    stepRow(index)
                }
            }
            .padding(.trailing, 2)
        }
        .scrollIndicators(.never)
        .frame(height: listHeight)
    }

    /// Three rows visible at a time; the list scrolls beyond that so the sheet
    /// stays a predictable height even at the 8-step cap.
    private var listHeight: CGFloat {
        max(96, min(CGFloat(steps.count), 3) * 116)
    }

    private func stepRow(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 7)
                .onDrag {
                    dragging = index
                    return NSItemProvider(object: "\(index)" as NSString)
                }
                .help("Drag to reorder")

            Text("\(index + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Step kind", selection: $steps[index].kind) {
                        ForEach(ActionKind.stepCases) { kind in
                            Label(kind.title, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 192)

                    Spacer(minLength: 4)

                    Stepper(
                        value: delay(index),
                        in: 0...SequenceLimits.maxStepDelayMilliseconds,
                        step: 10
                    ) {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(steps[index].clampedDelay) ms")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .controlSize(.small)
                    .help("Wait before this step fires (0–500 ms)")
                }

                ActionFieldsView(fields: $steps[index], compact: true)
            }

            VStack(spacing: 1) {
                IconButton("chevron.up", help: "Move up") { move(index, by: -1) }
                    .disabled(index == 0)
                IconButton("chevron.down", help: "Move down") { move(index, by: 1) }
                    .disabled(index == steps.count - 1)
                IconButton("plus.square.on.square", help: "Duplicate step") {
                    steps.duplicateStep(at: index)
                }
                .disabled(!steps.canAddStep)
                IconButton("trash", help: "Delete step") {
                    steps.deleteStep(at: index)
                }
            }
            .padding(.top, 1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary)
        )
        .onDrop(
            of: [.text],
            delegate: StepDropDelegate(destination: index, steps: $steps, dragging: $dragging)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                steps.addStep()
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            .disabled(!steps.canAddStep)

            if !steps.canAddStep {
                Text("At the \(SequenceLimits.maxSteps)-step limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(steps.count) of \(SequenceLimits.maxSteps) steps")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Editing

    /// A delay as a `Binding<Int>` clamped to the step's own limits, so a
    /// hand-edited config that stored 9 999 ms is shown and edited as 500 ms.
    private func delay(_ index: Int) -> Binding<Int> {
        Binding(
            get: {
                steps.indices.contains(index) ? steps[index].clampedDelay : 0
            },
            set: { newValue in
                guard steps.indices.contains(index) else { return }
                steps[index].delayMilliseconds = min(
                    max(newValue, 0),
                    SequenceLimits.maxStepDelayMilliseconds
                )
            }
        )
    }

    private func move(_ index: Int, by offset: Int) {
        steps.moveStep(from: index, to: index + offset)
    }
}

/// A compact borderless icon button for the per-row controls.
private struct IconButton: View {
    let symbolName: String
    let help: String
    let action: () -> Void

    init(_ symbolName: String, help: String, action: @escaping () -> Void) {
        self.symbolName = symbolName
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 17)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Live reorder while a row's drag handle is over another row.
///
/// SwiftUI's `List` reordering needs an edit mode on some macOS versions, so the
/// step list is a plain `VStack` with `onDrag`/`onDrop`. Up/down buttons in each
/// row are the keyboard- and accessibility-friendly equivalent.
private struct StepDropDelegate: DropDelegate {
    let destination: Int
    @Binding var steps: [ActionStep]
    @Binding var dragging: Int?

    func dropEntered(info: DropInfo) {
        guard let source = dragging,
              source != destination,
              steps.indices.contains(source),
              steps.indices.contains(destination) else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            _ = steps.moveStep(from: source, to: destination)
        }
        dragging = destination
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
