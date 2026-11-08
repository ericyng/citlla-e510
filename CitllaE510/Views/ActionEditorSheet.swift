import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ActionEditorSheet: View {
    let button: ButtonBinding
    @EnvironmentObject private var config: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MouseAction

    init(button: ButtonBinding) {
        self.button = button
        _draft = State(initialValue: button.action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "computermouse")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(button.name).font(.headline)
                    Text(button.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Picker("Action", selection: $draft.kind) {
                    ForEach(ActionKind.allCases) { kind in
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
                            Label(action.title, systemImage: action.symbolName).tag(action)
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
                    config.setAction(draft, for: button.button)
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
