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
/// Deliberately a smaller copy of `ActionEditorSheet` rather than a new target
/// on it: the shared action editor is being reworked by the macro-ui track, and
/// the Scrolling section must not block on or collide with it. Once
/// `ActionFieldsView` exists this sheet can collapse into it.
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

            Divider()

            Form {
                Picker("Action", selection: $draft.kind) {
                    // `.sequence` is intentionally absent until the step editor
                    // lands; the picker must never offer an option with no UI.
                    ForEach(ActionKind.editableCases) { kind in
                        Label(kind.title, systemImage: kind.symbolName).tag(kind)
                    }
                }

                switch draft.kind {
                case .none:
                    Text("This tilt will scroll horizontally.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                case .system:
                    Picker("System action", selection: $draft.system) {
                        ForEach(SystemAction.allCases) { action in
                            Label(
                                action.unavailableNote == nil
                                    ? action.title
                                    : "\(action.title) (not available)",
                                systemImage: action.symbolName
                            )
                            .tag(action)
                        }
                    }
                    if let note = draft.system.unavailableNote {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                case .keyboardShortcut:
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(
                            keyCode: $draft.keyCode,
                            modifiers: $draft.modifiers,
                            hasShortcut: $draft.hasShortcut
                        )
                    }
                    Text("Click Record, then press the key combination. Escape cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .mouseClick:
                    Picker("Click", selection: $draft.click) {
                        ForEach(MouseClickKind.allCases) { click in
                            Text(click.title).tag(click)
                        }
                    }

                case .openApp:
                    LabeledContent("Application") {
                        HStack {
                            TextField("/Applications/Example.app", text: $draft.text)
                                .textFieldStyle(.roundedBorder)
                            Button("Choose…") { chooseApp() }
                        }
                    }

                case .openURL:
                    TextField("https://example.com", text: $draft.text)
                        .textFieldStyle(.roundedBorder)

                case .shellCommand:
                    TextField("/usr/bin/say hello", text: $draft.text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Text("Runs through /bin/zsh -lc. Only use commands you trust.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .sequence:
                    // Reachable only from a config written by a later build.
                    Text("This version cannot edit sequences.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    config.config.scroll.setAction(draft, for: direction)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.kind == .keyboardShortcut && !draft.hasShortcut)
            }
            .padding(16)
        }
        .frame(width: 560)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            draft.text = url.path
        }
    }
}
