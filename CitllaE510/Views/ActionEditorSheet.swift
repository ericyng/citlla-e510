import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ActionEditorSheet: View {
    /// What is being edited: a mouse button, or a key the mouse sends.
    enum Target: Identifiable {
        case button(ButtonBinding)
        case shortcut(ShortcutBinding)

        var id: String {
            switch self {
            case .button(let binding): "button-\(binding.button)"
            case .shortcut(let binding): "shortcut-\(binding.id)"
            }
        }

        var name: String {
            switch self {
            case .button(let binding): binding.name
            case .shortcut(let binding): binding.name
            }
        }

        var subtitle: String {
            switch self {
            case .button(let binding): binding.subtitle
            case .shortcut(let binding): binding.subtitle
            }
        }

        var symbolName: String {
            switch self {
            case .button: "computermouse"
            case .shortcut: "keyboard"
            }
        }

        var action: MouseAction {
            switch self {
            case .button(let binding): binding.action
            case .shortcut(let binding): binding.action
            }
        }
    }

    let target: Target
    @EnvironmentObject private var config: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MouseAction

    init(target: Target) {
        self.target = target
        _draft = State(initialValue: target.action)
    }

    init(button: ButtonBinding) {
        self.init(target: .button(button))
    }

    init(shortcut: ShortcutBinding) {
        self.init(target: .shortcut(shortcut))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: target.symbolName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name).font(.headline)
                    Text(target.subtitle).font(.caption).foregroundStyle(.secondary)
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
                    Text("This button will behave normally.")
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

                if case .shortcut = target {
                    Text("Only the mouse's own presses of this key are remapped. The same shortcut on the keyboard still works normally.")
                        .font(.caption)
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
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.kind == .keyboardShortcut && !draft.hasShortcut)
            }
            .padding(16)
        }
        .frame(width: 560)
    }

    private func save() {
        switch target {
        case .button(let binding):
            config.setAction(draft, for: binding.button)
        case .shortcut(let binding):
            config.setAction(draft, forShortcut: binding.id)
        }
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
