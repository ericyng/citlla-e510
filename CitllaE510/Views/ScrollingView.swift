import AppKit
import SwiftUI

/// The Scrolling section: direction inversion, the side wheel, and the honest
/// pointer-speed link.
///
/// Self-contained on purpose: it needs only `ConfigStore` in the environment,
/// so the app shell can host it as a sidebar section without wiring anything
/// else up.
struct ScrollingView: View {
    @EnvironmentObject private var config: ConfigStore

    @State private var editing: TiltDirection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Scrolling")
                    .font(.largeTitle.bold())
                Text("Change which way the wheel scrolls, and give the side wheel a job. Everything here applies the moment it is switched on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Form {
                Section {
                    Toggle("Invert vertical scrolling", isOn: binding(\.invertVertical))
                    Toggle("Invert horizontal scrolling", isOn: binding(\.invertHorizontal))
                } header: {
                    Text("Direction")
                } footer: {
                    Text("Inversion rewrites the scroll event in place, so phase and momentum scrolling from a trackpad keep working. The master switch on the Buttons page turns all remapping off, including this.")
                }

                Section {
                    TiltRow(direction: .left, action: config.config.scroll.tiltLeft) {
                        editing = .left
                    }
                    TiltRow(direction: .right, action: config.config.scroll.tiltRight) {
                        editing = .right
                    }
                } header: {
                    Text("Side wheel")
                } footer: {
                    Text("The side wheel arrives as a horizontal scroll (AC Pan). Give a direction an action and that tilt fires once per flick and stops scrolling sideways; leave it on Pass through and it scrolls horizontally as it does now. A trackpad's own horizontal scrolling is left alone.")
                }

                Section {
                    LabeledContent("Pointer speed") {
                        Button("Open Mouse Settings…") { openMouseSettings() }
                    }
                    Text("Pointer speed and acceleration live in macOS and have no public API, so this app cannot move them. The button opens System Settings → Mouse, where the slider lives.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Pointer")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Scroll changes need Accessibility access, the same as button remapping.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .sheet(item: $editing) { direction in
            TiltActionSheet(direction: direction, action: config.config.scroll.action(for: direction))
                .environmentObject(config)
        }
    }

    /// A binding straight into `config.config.scroll`, so every switch saves as
    /// it is flipped.
    private func binding(_ keyPath: WritableKeyPath<ScrollSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { config.config.scroll[keyPath: keyPath] },
            set: { config.config.scroll[keyPath: keyPath] = $0 }
        )
    }

    private func openMouseSettings() {
        // The Mouse pane of System Settings on macOS 15+. Deep links to the old
        // System Preferences panes no longer work, and a failure here is not
        // worth an alert: System Settings is one search away.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Mouse-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct TiltRow: View {
    let direction: TiltDirection
    let action: MouseAction
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 12) {
                Image(systemName: direction.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(action.isBound ? Color.accentColor : Color.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(direction.title)
                        .font(.body.weight(.medium))
                    Text(action.isBound ? "Fires once per flick" : "Scrolls horizontally, as now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: action.symbolName)
                        .foregroundStyle(.secondary)
                    Text(action.summary)
                        .foregroundStyle(action.isBound ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 280, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

/// Edits one tilt action.
///
/// The same controls as the button editor: `ActionFieldsView` for every kind and
/// `MacroEditorView` for a sequence, so a tilt can be a chord click or a short
/// sequence exactly like a button can. The only difference is the empty text and
/// the save target.
private struct TiltActionSheet: View {
    let direction: TiltDirection

    @EnvironmentObject private var config: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MouseAction

    init(direction: TiltDirection, action: MouseAction) {
        self.direction = direction
        _draft = State(initialValue: action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Picker("Action", selection: $draft.kind) {
                    ForEach(ActionKind.editableCases) { kind in
                        Label(kind.title, systemImage: kind.symbolName).tag(kind)
                    }
                }

                if draft.kind == .sequence {
                    MacroEditorView(steps: $draft.steps)
                } else {
                    ActionFieldsView(
                        action: $draft,
                        emptyText: "This tilt will scroll horizontally."
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            HStack {
                if draft.kind == .sequence, !draft.steps.isEmpty {
                    Text(ActionKind.sequence.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    config.config.scroll.setAction(draft, for: direction)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 640)
        .onChange(of: draft.kind) { _, newKind in
            // Same rule as the button editor: a sequence with no steps would be
            // an unbound action and quietly turn the tilt back into scrolling.
            if newKind == .sequence, draft.steps.isEmpty {
                draft.steps = [ActionStep(kind: .keyboardShortcut)]
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: direction.symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(direction.title).font(.headline)
                Text("Side wheel, fires once per flick")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var canSave: Bool {
        switch draft.kind {
        case .keyboardShortcut:
            draft.hasShortcut
        case .sequence:
            draft.steps.contains { $0.kind != .none && $0.kind != .sequence }
        default:
            true
        }
    }
}
