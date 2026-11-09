import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case mouse
    case buttons
    case permissions
    case about
}

struct SettingsView: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var eventTap: EventTapService
    @EnvironmentObject private var loginItem: LoginItemManager

    @State private var selection: SettingsTab

    init(initialTab: SettingsTab = .mouse) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            MouseSettingsView(selection: $selection)
                .tabItem { Label("Mouse", systemImage: "computermouse") }
                .tag(SettingsTab.mouse)
            ButtonsSettingsView()
                .tabItem { Label("Buttons", systemImage: "list.bullet") }
                .tag(SettingsTab.buttons)
            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .environmentObject(config)
        .environmentObject(eventTap)
        .environmentObject(loginItem)
        .frame(width: 760, height: 560)
        .onAppear {
            NSApplication.shared.activate()
        }
    }
}

struct MouseSettingsView: View {
    @Binding var selection: SettingsTab
    @EnvironmentObject private var config: ConfigStore

    @State private var editing: ActionEditorSheet.Target?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Citlla E510")
                    .font(.largeTitle.bold())
                Text("Your mouse's nine controls, numbered as they are on the CITLLA diagram. Click one to choose what it does on the Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 20) {
                MouseRenderPair(height: 232)

                ScrollView {
                    MouseControlLegend(
                        actions: actions(for:),
                        onSelect: edit(_:)
                    )
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 8)
            Divider()

            HStack(spacing: 10) {
                Image(systemName: "hand.tap")
                    .foregroundStyle(.secondary)
                Text("Not sure which number is which? Open the tester and press each control — it reports exactly what the mouse sends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Test Buttons…") {
                    WindowManager.shared.showTester()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .sheet(item: $editing) { target in
            ActionEditorSheet(target: target)
                .environmentObject(config)
        }
    }

    /// The actions behind a callout. Most controls send one mouse button; the
    /// thumb buttons send two different keystrokes.
    private func actions(for control: MouseControl) -> [MouseAction] {
        if let button = control.hidButtons.first {
            return [config.binding(for: button).action]
        }
        return shortcutBindings(for: control).map(\.action)
    }

    private func shortcutBindings(for control: MouseControl) -> [ShortcutBinding] {
        config.shortcutBindings.filter { MouseMap.control(forShortcut: $0)?.number == control.number }
    }

    private func edit(_ control: MouseControl) {
        if let button = control.hidButtons.first {
            editing = .button(config.binding(for: button))
            return
        }
        let shortcuts = shortcutBindings(for: control)
        if shortcuts.count == 1, let shortcut = shortcuts.first {
            editing = .shortcut(shortcut)
        } else {
            // Two thumb buttons share callout 8; the Buttons tab lists each one
            // separately so both can be edited.
            selection = .buttons
        }
    }
}

struct ButtonsSettingsView: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var eventTap: EventTapService

    @State private var editing: ActionEditorSheet.Target?
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Citlla E510")
                    .font(.largeTitle.bold())
                Text("Remap the extra buttons on your CITLLA PRO MAX E510 mouse. Click a button below to choose what it does.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            List {
                Section {
                    Toggle(
                        "Enable button remapping",
                        isOn: Binding(
                            get: { config.config.enabled },
                            set: { newValue in
                                config.config.enabled = newValue
                                if newValue { eventTap.startIfNeeded() }
                            }
                        )
                    )
                } footer: {
                    Text("When disabled, every mouse button behaves normally.")
                }

                Section {
                    if config.shortcutBindings.isEmpty {
                        Text("Nothing learned yet. Press the thumb buttons while the tester is open.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(config.shortcutBindings) { binding in
                            Button {
                                editing = .shortcut(binding)
                            } label: {
                                BindingRow(
                                    symbol: "keyboard",
                                    name: binding.name,
                                    subtitle: binding.subtitle,
                                    action: binding.action
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Mouse Keystrokes")
                } footer: {
                    Text("This mouse sends its thumb buttons as ⌃← and ⌃→, and the ninth control as ⌃⌘F, instead of mouse buttons. They are remapped here, and only when the mouse itself sent the key — your keyboard still works normally.")
                }

                Section("Mouse Buttons") {
                    ForEach(config.config.bindings) { binding in
                        Button {
                            editing = .button(binding)
                        } label: {
                            BindingRow(
                                symbol: "computermouse",
                                name: binding.name,
                                subtitle: binding.subtitle,
                                action: binding.action
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 10) {
                Circle()
                    .fill(eventTap.isRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(eventTap.isRunning ? "Listening for mouse buttons" : (eventTap.lastError ?? "Event tap is not running"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !PermissionManager.hasInputMonitoring {
                        Text("Input Monitoring is off — the thumb buttons cannot be recognised.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button("Retry") { eventTap.restart() }
                    .controlSize(.small)
                Button("Reset Defaults…") { confirmReset = true }
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .sheet(item: $editing) { target in
            ActionEditorSheet(target: target)
                .environmentObject(config)
        }
        .confirmationDialog(
            "Reset all buttons to the default layout?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset Defaults", role: .destructive) {
                config.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The two thumb buttons will go back and forward. The mouse's other extra buttons will do nothing.")
        }
    }
}

private struct BindingRow: View {
    let symbol: String
    let name: String
    let subtitle: String
    let action: MouseAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(action.isBound ? Color.accentColor : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                Text(subtitle)
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
}
