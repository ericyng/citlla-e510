import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Profiles section: the global map, plus one rule per app that can
/// override any button or mouse key.
///
/// The Default row is always visible so it is obvious what happens when no
/// profile is active. Profiles only ever *add* overrides: a control the profile
/// does not mention (or leaves unbound) keeps the global action, and a profile
/// switched off is ignored entirely.
struct ProfilesView: View {
    @EnvironmentObject private var config: ConfigStore

    @State private var editingProfile: AppProfile?
    @State private var removing: AppProfile?
    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    defaultRow
                    Divider()
                        .padding(.leading, 60)

                    if config.config.profiles.isEmpty {
                        emptyState
                    } else {
                        ForEach(config.config.profiles) { profile in
                            profileRow(profile)
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(profileID: profile.id)
                .environmentObject(config)
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "this profile")?",
            isPresented: removingBinding,
            presenting: removing
        ) { profile in
            Button("Remove Profile", role: .destructive) {
                config.config.removeProfile(id: profile.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("The overrides for \(profile.id) are deleted and the app goes back to the global map.")
        }
        .alert("Could not add profile", isPresented: addErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(addError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Profiles")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    addProfile()
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
                .help("Choose an app to give it its own button and mouse-key map.")
            }

            Text("Give one app its own button and mouse-key map. Anything a profile does not override keeps using the global map, and Default applies whenever no profile is active.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Default

    private var defaultRow: some View {
        HStack(spacing: 12) {
            ProfileIcon(image: nil, symbol: "macwindow")

            VStack(alignment: .leading, spacing: 2) {
                Text("Default")
                    .font(.body.weight(.medium))
                Text("Every app without a profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text("\(boundGlobalCount) of \(MouseMap.controls.count) controls bound globally")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// Every control with an action in the global map: buttons and the keys the
    /// mouse sends. This is what a profile inherits.
    private var boundGlobalCount: Int {
        config.config.bindings.filter { $0.action.isBound }.count
            + config.shortcutBindings.filter { $0.action.isBound }.count
    }

    // MARK: - Profiles

    private func profileRow(_ profile: AppProfile) -> some View {
        HStack(spacing: 12) {
            ProfileIcon(
                image: appIcon(for: profile.id),
                symbol: "app.fill",
                dimmed: !profile.enabled
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(profile.enabled ? .primary : .secondary)
                Text(profile.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            Text(overrideSummary(profile))
                .font(.callout)
                .foregroundStyle(profile.overrideCount == 0 ? .secondary : .primary)
                .frame(minWidth: 92, alignment: .trailing)

            Toggle("Enabled", isOn: enabledBinding(for: profile.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(profile.enabled ? "Turn this profile off; the app uses the global map" : "Turn this profile on")

            Button("Edit") { editingProfile = profile }
                .controlSize(.small)

            Button("Remove", role: .destructive) { removing = profile }
                .controlSize(.small)
                .padding(.trailing, 20)
        }
        .padding(.leading, 20)
        .padding(.vertical, 10)
    }

    private func overrideSummary(_ profile: AppProfile) -> String {
        let count = profile.overrideCount
        switch count {
        case 0: return "No overrides"
        case 1: return "1 override"
        default: return "\(count) overrides"
        }
    }

    private func enabledBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { config.config.profiles.first { $0.id == id }?.enabled ?? false },
            set: { newValue in
                guard let index = config.config.profiles.firstIndex(where: { $0.id == id }) else { return }
                config.config.profiles[index].enabled = newValue
            }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.badge.plus")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("No app profiles yet")
                .font(.title3.weight(.semibold))
            Text("Add an app to give it its own button map, such as opening a new tab with the middle click in Chrome only. Anything you leave alone keeps using the global map, and a profile can be switched off again at any time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("Add App…") { addProfile() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    // MARK: - Adding

    private func addProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add Profile"
        panel.message = "Choose an app to give it its own button and mouse-key map."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addProfile(at: url)
    }

    private func addProfile(at url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            addError = "That file is not an application bundle with a bundle identifier."
            return
        }
        guard id != AppConfig.ownBundleIdentifier else {
            addError = "Citlla E510 cannot have a profile for itself. Its own window must keep using the global map."
            return
        }
        guard !config.config.profiles.contains(where: { $0.id == id }) else {
            addError = "A profile for \(displayName(of: bundle, at: url)) already exists."
            return
        }

        let profile = AppProfile(id: id, name: displayName(of: bundle, at: url))
        config.config.setProfile(profile)
        config.config.profiles.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func displayName(of bundle: Bundle, at url: URL) -> String {
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.isEmpty {
            return name
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// The app's real icon, when the bundle is still installed. A profile whose
    /// app has been deleted falls back to a generic symbol rather than a blank.
    private func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Small bindings

    private var removingBinding: Binding<Bool> {
        Binding(
            get: { removing != nil },
            set: { if !$0 { removing = nil } }
        )
    }

    private var addErrorBinding: Binding<Bool> {
        Binding(
            get: { addError != nil },
            set: { if !$0 { addError = nil } }
        )
    }
}

// MARK: - Row icon

/// The app icon (or a symbol when the bundle cannot be resolved) at a fixed
/// size, so rows line up whether or not the app is installed.
private struct ProfileIcon: View {
    let image: NSImage?
    let symbol: String
    var dimmed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(dimmed ? Color.secondary : Color.primary)
            }
        }
        .frame(width: 32, height: 32)
        .opacity(dimmed ? 0.45 : 1)
    }
}

// MARK: - Editing one profile

/// The list of every control in the global map, with the profile's override
/// beside it. Editing one row opens `ProfileOverrideSheet`, which owns a single
/// draft action.
private struct ProfileEditorSheet: View {
    let profileID: String

    @EnvironmentObject private var config: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var editing: ActionEditorSheet.Target?

    private var profile: AppProfile? {
        config.config.profiles.first { $0.id == profileID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if let profile {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows(for: profile)) { row in
                            rowView(row)
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            } else {
                Text("This profile was removed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            footer
        }
        .frame(width: 700, height: 560)
        .sheet(item: $editing) { target in
            ProfileOverrideSheet(
                profileID: profileID,
                target: target,
                override: override(for: target)
            )
            .environmentObject(config)
        }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.name ?? profileID)
                    .font(.headline)
                Text(profile.map { "\($0.id) · \(summary($0))" } ?? profileID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if profile != nil {
                Toggle("Enabled", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Overrides apply while this app is frontmost. Everything else follows the global map, so the profile only has to mention what is different.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func summary(_ profile: AppProfile) -> String {
        let count = profile.overrideCount
        return count == 1 ? "1 override" : "\(count) overrides"
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { profile?.enabled ?? false },
            set: { newValue in
                guard let index = config.config.profiles.firstIndex(where: { $0.id == profileID }) else { return }
                config.config.profiles[index].enabled = newValue
            }
        )
    }

    // MARK: Rows

    /// One control: the target it edits, its global action, and the profile's
    /// override when there is one.
    private struct ControlRow: Identifiable {
        let target: ActionEditorSheet.Target
        let global: MouseAction
        let override: MouseAction?

        var id: String { target.id }
    }

    /// Every globally bound button, plus every mouse-key control (bound or not,
    /// because a profile can give an unused key a job). A button that is
    /// unbound globally only appears once the profile overrides it, so the list
    /// never offers overrides for buttons this mouse does not have.
    private func rows(for profile: AppProfile) -> [ControlRow] {
        let buttons = config.config.bindings
            .sorted { $0.button < $1.button }
            .filter { binding in
                binding.action.isBound || profile.buttonAction(for: binding.button) != nil
            }
            .map { binding in
                ControlRow(
                    target: .button(binding),
                    global: binding.action,
                    override: profile.buttonAction(for: binding.button)
                )
            }

        let keys = config.config.shortcutBindings.map { binding in
            ControlRow(
                target: .shortcut(binding),
                global: binding.action,
                override: profile.shortcutAction(for: binding.id)
            )
        }

        return buttons + keys
    }

    private func rowView(_ row: ControlRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: row.target.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(row.override == nil ? Color.secondary : Color.accentColor)
                .frame(width: 22, height: 22)
                .padding(.leading, 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.target.name)
                    .font(.body.weight(.medium))
                Text("Global: \(row.global.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.override?.summary ?? "Follows global")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(row.override == nil ? .secondary : .primary)
                if row.override != nil {
                    Text("Profile override")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 260, alignment: .trailing)

            Button(row.override == nil ? "Override…" : "Edit") {
                editing = row.target
            }
            .controlSize(.small)
            .padding(.trailing, 20)
        }
        .padding(.vertical, 10)
    }

    private func override(for target: ActionEditorSheet.Target) -> MouseAction? {
        guard let profile else { return nil }
        switch target {
        case .button(let binding):
            return profile.buttonAction(for: binding.button)
        case .shortcut(let binding):
            return profile.shortcutAction(for: binding.id)
        }
    }
}

// MARK: - Editing one override

/// Edits a single control's override for one profile.
///
/// The controls are the app's shared editor pieces — `ActionFieldsView` for
/// every kind and `MacroEditorView` for a sequence — so a per-app override can
/// be a chord or a sequence exactly like a global binding, and the two editors
/// cannot drift. "Use Global" removes the override instead of saving one.
private struct ProfileOverrideSheet: View {
    let profileID: String
    let target: ActionEditorSheet.Target

    @EnvironmentObject private var config: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MouseAction

    init(profileID: String, target: ActionEditorSheet.Target, override: MouseAction?) {
        self.profileID = profileID
        self.target = target
        _draft = State(initialValue: override ?? target.action)
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
                        emptyText: "This control will use the global action."
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            HStack {
                Button("Use Global") { clear() }
                    .help("Remove the override; this control follows the global map again.")
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
            // Same rule as the other editors: a sequence with no steps is
            // unbound, which would silently hand the control back to the
            // global map. Start with one row so the kind is usable immediately.
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
                Text(target.name)
                    .font(.headline)
                Text(profileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Global: \(target.action.summary)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(20)
    }

    private var profileName: String {
        config.config.profiles.first { $0.id == profileID }?.name ?? profileID
    }

    private var profileIndex: Int? {
        config.config.profiles.firstIndex { $0.id == profileID }
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

    private func save() {
        save(draft)
    }

    private func clear() {
        save(nil)
        dismiss()
    }

    private func save(_ action: MouseAction?) {
        guard let index = profileIndex else { return }
        switch target {
        case .button(let binding):
            config.config.profiles[index].setButtonAction(action, for: binding.button)
        case .shortcut(let binding):
            config.config.profiles[index].setShortcutAction(action, for: binding.id)
        }
    }
}
