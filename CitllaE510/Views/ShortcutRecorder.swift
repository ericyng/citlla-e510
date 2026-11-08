import AppKit
import SwiftUI

struct ShortcutRecorder: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt
    @Binding var hasShortcut: Bool

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(hasShortcut ? KeyCodeMap.describe(keyCode: keyCode, modifiers: modifiers) : "Not recorded")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(hasShortcut ? .primary : .secondary)
                .frame(minWidth: 130, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.25))
                )

            Button(isRecording ? "Press keys…" : "Record") {
                isRecording ? stopRecording() : startRecording()
            }

            if hasShortcut && !isRecording {
                Button("Clear") {
                    keyCode = 0
                    modifiers = 0
                    hasShortcut = false
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            keyCode = event.keyCode
            modifiers = flags.rawValue
            hasShortcut = true
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
