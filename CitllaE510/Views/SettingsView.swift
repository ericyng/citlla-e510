import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var eventTap: EventTapService
    @EnvironmentObject private var loginItem: LoginItemManager

    var body: some View {
        TabView {
            ButtonsSettingsView()
                .tabItem { Label("Buttons", systemImage: "computermouse") }
            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .environmentObject(config)
        .environmentObject(eventTap)
        .environmentObject(loginItem)
        .frame(width: 760, height: 560)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

struct ButtonsSettingsView: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var eventTap: EventTapService

    @State private var editing: ButtonBinding?
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

                Section("Buttons") {
                    ForEach(config.config.bindings) { binding in
                        Button {
                            editing = binding
                        } label: {
                            ButtonRow(binding: binding)
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
                Text(eventTap.isRunning ? "Listening for mouse buttons" : (eventTap.lastError ?? "Event tap is not running"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Retry") { eventTap.restart() }
                    .controlSize(.small)
                Button("Reset Defaults…") { confirmReset = true }
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .sheet(item: $editing) { binding in
            ActionEditorSheet(button: binding)
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
            Text("Button 4 will go back, button 5 will go forward, and all other extra buttons will do nothing.")
        }
    }
}

private struct ButtonRow: View {
    let binding: ButtonBinding

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "computermouse")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(binding.action.isBound ? Color.accentColor : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(binding.name)
                    .font(.body.weight(.medium))
                Text(binding.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: binding.action.symbolName)
                    .foregroundStyle(.secondary)
                Text(binding.action.summary)
                    .foregroundStyle(binding.action.isBound ? .primary : .secondary)
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
