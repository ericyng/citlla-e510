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

    let initialKind: ActionKind?

    init(target: Target, initialKind: ActionKind? = nil) {
        self.target = target
        self.initialKind = initialKind
        var action = target.action
        if let kind = initialKind {
            action.kind = kind
            if kind == .sequence, action.steps.isEmpty {
                action.steps = [ActionStep(kind: .keyboardShortcut)]
            }
        }
        _draft = State(initialValue: action)
    }

    init(button: ButtonBinding) {
        self.init(target: .button(button))
    }

    init(shortcut: ShortcutBinding) {
        self.init(target: .shortcut(shortcut))
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
                        emptyText: "This button will behave normally."
                    )
                }

                if case .shortcut = target {
                    Text("Only the mouse's own presses of this key are remapped. The same shortcut on the keyboard still works normally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 640)
        .onChange(of: draft.kind) { _, newKind in
            // Switching to Sequence with no steps used to leave the editor with
            // nothing to edit. Start with one row so the kind is usable
            // immediately; the Presets menu is the quicker route for real work.
            if newKind == .sequence, draft.steps.isEmpty {
                draft.steps = [ActionStep(kind: .keyboardShortcut)]
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: target.symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).font(.headline)
                Text(target.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                ForEach(ActionPreset.all) { preset in
                    Button {
                        draft = preset.make()
                    } label: {
                        Text(preset.name)
                    }
                    .help(preset.detail)
                }
            } label: {
                Label("Presets", systemImage: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Fill the editor with a ready-made action, including sequences and chords.")
        }
        .padding(20)
    }

    private var canSave: Bool {
        switch draft.kind {
        case .keyboardShortcut:
            draft.hasShortcut
        case .sequence:
            // An empty sequence is `isBound == false` and would quietly turn the
            // button into a pass-through; require at least one real step.
            draft.steps.contains { $0.kind != .none && $0.kind != .sequence }
        default:
            true
        }
    }

    private func save() {
        switch target {
        case .button(let binding):
            config.setAction(draft, for: binding.button)
        case .shortcut(let binding):
            config.setAction(draft, forShortcut: binding.id)
        }
    }
}

// MARK: - Shared per-kind fields

/// The controls behind one action kind: system picker, shortcut recorder, click
/// and its chord modifiers, app picker, URL and shell fields.
///
/// A `MouseAction` and an `ActionStep` carry the same per-kind fields, so both
/// the sheet and a step row bind their own value through this view. Nothing in
/// here can create a nested sequence: step callers only ever bind an
/// `ActionStep`, whose kind picker excludes `.sequence`.
struct ActionFieldsView: View {
    @Binding var fields: ActionStep
    /// A step row inside the sequence editor. Same controls, tighter spacing and
    /// no explanatory captions.
    var compact = false
    var emptyText = "Does nothing. A step like this is skipped when the sequence runs."

    init(
        fields: Binding<ActionStep>,
        compact: Bool = false,
        emptyText: String = "Does nothing. A step like this is skipped when the sequence runs."
    ) {
        self._fields = fields
        self.compact = compact
        self.emptyText = emptyText
    }

    /// The same controls for a whole action, so a sheet and a step row cannot
    /// drift. `apply` preserves `steps`, so editing the fields of a sequence
    /// action never discards its step list.
    init(
        action: Binding<MouseAction>,
        compact: Bool = false,
        emptyText: String = "Does nothing. A step like this is skipped when the sequence runs."
    ) {
        self.init(
            fields: Binding(
                get: { action.wrappedValue.asStep },
                set: { action.wrappedValue.apply($0) }
            ),
            compact: compact,
            emptyText: emptyText
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            switch fields.kind {
            case .none:
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .system:
                Picker("System action", selection: $fields.system) {
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
                if let note = fields.system.unavailableNote {
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
                ShortcutRecorder(
                    keyCode: $fields.keyCode,
                    modifiers: $fields.modifiers,
                    hasShortcut: $fields.hasShortcut
                )
                if !compact {
                    Text("Click Record, then press the key combination. Escape cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .mouseClick:
                Picker("Click", selection: $fields.click) {
                    ForEach(MouseClickKind.allCases) { click in
                        Text(click.title).tag(click)
                    }
                }
                chordRow
                if !compact {
                    Text("The modifiers are held down around the click, so ⌘-click opens a link in a new tab and ⌥-click downloads it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .openApp:
                HStack(spacing: 8) {
                    TextField("/Applications/Example.app", text: $fields.text)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseApp() }
                }

            case .openURL:
                TextField("https://example.com", text: $fields.text)
                    .textFieldStyle(.roundedBorder)

            case .shellCommand:
                TextField("/usr/bin/say hello", text: $fields.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                if !compact {
                    Text("Runs through /bin/zsh -lc. Only use commands you trust.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .sequence:
                Text("A sequence cannot contain another sequence.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// ⌃ ⌥ ⇧ ⌘ for a `.mouseClick`, with a live "⌘ Left Click" preview. This is
    /// the only way to reach the chord support the executor already has.
    private var chordRow: some View {
        HStack(spacing: 6) {
            Text("Hold")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)

            ForEach(ChordModifier.allCases) { modifier in
                Toggle(modifier.symbol, isOn: chordBinding(modifier))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help(modifier.title)
            }

            Text(MouseAction.describe(click: fields.click, modifiers: fields.clickModifiers))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(fields.clickModifiers == 0 ? .secondary : .primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
                .padding(.leading, 4)

            Spacer(minLength: 0)
        }
    }

    private func chordBinding(_ modifier: ChordModifier) -> Binding<Bool> {
        Binding(
            get: { ChordModifier.isOn(modifier, in: fields.clickModifiers) },
            set: { isOn in
                fields.clickModifiers = ChordModifier.setting(
                    modifier,
                    on: isOn,
                    in: fields.clickModifiers
                )
            }
        )
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
            fields.text = url.path
        }
    }
}
