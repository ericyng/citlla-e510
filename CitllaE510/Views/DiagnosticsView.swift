import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var eventTap: EventTapService
    @StateObject private var monitor = HIDMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Diagnostics")
                        .font(.largeTitle.bold())
                    Spacer()
                    Circle()
                        .fill(monitor.isRunning ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(monitor.isRunning ? "Reading HID reports" : "HID monitor stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Press the mouse buttons and watch the raw HID usage numbers below. Button events use usage page 0x09; the usage is the button number used by the remapper.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if let error = monitor.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error).font(.callout)
                        Text("Input Monitoring is only needed for this diagnostics window. Remapping still works with Accessibility alone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Grant Access") {
                        _ = PermissionManager.requestInputMonitoring()
                        PermissionManager.openInputMonitoringSettings()
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            if !monitor.devices.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(monitor.devices) { device in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).font(.caption.weight(.semibold))
                                Text(device.usageDescription)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(device.transportDescription)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 10)
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if monitor.events.isEmpty {
                            Text(monitor.isRunning ? "Waiting for input…" : "Start the monitor to see events.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 20)
                        }
                        ForEach(monitor.events) { entry in
                            HStack(spacing: 8) {
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.tertiary)
                                Text(entry.device)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 80, alignment: .leading)
                                Text(entry.summary)
                                    .foregroundStyle(color(for: entry))
                                if entry.isButton {
                                    Text("← button \(entry.usage)")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .font(.system(.caption, design: .monospaced))
                            .id(entry.id)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: monitor.events.count) { _, _ in
                    if let last = monitor.events.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                if monitor.isRunning {
                    Button("Stop") { monitor.stop() }
                } else {
                    Button("Start") { monitor.start() }
                }
                Button("Clear") { monitor.clearEvents() }
                if !PermissionManager.hasInputMonitoring {
                    Button("Request Input Monitoring") {
                        _ = PermissionManager.requestInputMonitoring()
                    }
                }
                Spacer()
                if let action = eventTap.lastAction {
                    Text(action)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(eventTap.isRunning ? "Remapper active" : "Remapper inactive")
                    .font(.caption)
                    .foregroundStyle(eventTap.isRunning ? .green : .orange)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func color(for entry: HIDEventEntry) -> Color {
        switch entry.usagePage {
        case 0x09: .accentColor
        case 0x0C: .purple
        case 0xFFB5: .orange
        default: .primary
        }
    }
}
