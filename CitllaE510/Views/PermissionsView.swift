import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject private var eventTap: EventTapService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.5)) { _ in
            let hasAccessibility = PermissionManager.hasAccessibility
            let hasInputMonitoring = PermissionManager.hasInputMonitoring

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Permissions")
                        .font(.largeTitle.bold())
                    Text("Citlla E510 needs Accessibility access to intercept and replace mouse button events. Input Monitoring is optional and only used by the diagnostics window.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    PermissionCard(
                        title: "Accessibility",
                        symbol: "hand.raised.fill",
                        description: "Required for button remapping. Allows Citlla E510 to see and replace mouse events before they reach other apps.",
                        status: hasAccessibility ? "Granted" : "Not granted",
                        isGranted: hasAccessibility,
                        primaryTitle: hasAccessibility ? "Open Settings" : "Request Access",
                        primarySymbol: hasAccessibility ? "gearshape" : "checkmark.shield"
                    ) {
                        if hasAccessibility {
                            PermissionManager.openAccessibilitySettings()
                        } else {
                            _ = PermissionManager.requestAccessibility()
                            PermissionManager.openAccessibilitySettings()
                        }
                    }

                    PermissionCard(
                        title: "Input Monitoring",
                        symbol: "eye.fill",
                        description: "Optional. Lets the diagnostics window read raw HID reports so you can identify unknown buttons and vendor-specific controls.",
                        status: PermissionManager.inputMonitoringStatusText,
                        isGranted: hasInputMonitoring,
                        primaryTitle: hasInputMonitoring ? "Open Settings" : "Request Access",
                        primarySymbol: hasInputMonitoring ? "gearshape" : "hand.point.up.left"
                    ) {
                        if hasInputMonitoring {
                            PermissionManager.openInputMonitoringSettings()
                        } else {
                            _ = PermissionManager.requestInputMonitoring()
                            PermissionManager.openInputMonitoringSettings()
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Circle()
                                    .fill(eventTap.isRunning ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(eventTap.isRunning ? "Event tap is active" : "Event tap is not active")
                                    .font(.body.weight(.medium))
                                Spacer()
                                Button("Restart Event Tap") { eventTap.restart() }
                            }
                            if let error = eventTap.lastError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("After granting Accessibility, restart the event tap. macOS may also require you to relaunch the app once after a rebuild.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("If Accessibility already says Granted but the tap still will not start, the grant went stale after a rebuild. Remove Citlla E510 from the Accessibility list and add it again, or run: tccutil reset Accessibility com.ericng.citllae510")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                        .padding(4)
                    }

                    Text("If Citlla E510 does not appear in the Accessibility list, drag \(Bundle.main.bundleURL.lastPathComponent) into the list from Finder, or quit and relaunch the app.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PermissionCard: View {
    let title: String
    let symbol: String
    let description: String
    let status: String
    let isGranted: Bool
    let primaryTitle: String
    let primarySymbol: String
    let action: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isGranted ? Color.green : Color.orange)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title).font(.headline)
                        Text(status)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            )
                            .foregroundStyle(isGranted ? Color.green : Color.orange)
                    }
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: action) {
                    Label(primaryTitle, systemImage: primarySymbol)
                }
                .controlSize(.large)
            }
            .padding(6)
        }
    }
}
