import SwiftUI

/// Lets the user pick which control a newly-built chord or sequence is assigned
/// to. The Actions section has no free-standing action store, so a new action
/// lands on a button or thumb key the same way an edited one does.
struct ControlPickerSheet: View {
    let onSelect: (ActionEditorSheet.Target) -> Void
    @EnvironmentObject private var config: ConfigStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assign to a control")
                .font(.headline)
            Text("Choose the button or mouse-sent key that will run this action.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                Section("Mouse buttons") {
                    ForEach(config.config.bindings.sorted(by: { $0.button < $1.button })) { binding in
                        Button {
                            onSelect(.button(binding))
                        } label: {
                            HStack {
                                Text(binding.name)
                                Spacer()
                                Text(binding.action.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Mouse-sent keys") {
                    ForEach(config.shortcutBindings) { binding in
                        Button {
                            onSelect(.shortcut(binding))
                        } label: {
                            HStack {
                                Text(binding.name)
                                Spacer()
                                Text(binding.action.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
        }
        .frame(width: 420, height: 360)
        .padding(.top, 12)
    }
}