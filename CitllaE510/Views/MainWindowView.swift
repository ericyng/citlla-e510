import AppKit
import SwiftUI

/// The app's main window: a sidebar of sections and a detail pane that hosts the
/// existing views unchanged.
///
/// The window only exists in `.regular` mode. `MainWindowView` tells
/// `WindowManager` when it appears and disappears so the Dock icon follows the
/// window, unless *Keep in Dock* is on.
///
/// This is a plain two-column layout rather than a `NavigationSplitView`: on
/// macOS 26 the split view's Liquid Glass sidebar and its column sizing can let
/// the content drive the layout to thousands of points tall, which pushes the
/// sidebar offscreen and breaks selection. A fixed sidebar beside the detail
/// keeps every section reachable and the sidebar visible.
struct MainWindowView: View {
    @EnvironmentObject private var windows: MainWindowState

    var body: some View {
        HStack(spacing: 0) {
            MainSidebar(selection: $windows.selection)
                .listStyle(.sidebar)
                .frame(width: 210)

            Divider()

            MainSectionContent(selection: windows.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Citlla E510")
        // The tester pane asks for 860pt; with the 210pt sidebar that is 1071.
        // Anything smaller would clip the tester rather than scroll it.
        .frame(minWidth: 1080, minHeight: 660)
        .onAppear { WindowManager.shared.mainWindowOpened() }
        .onDisappear { WindowManager.shared.mainWindowClosed() }
    }
}

/// The detail pane for one section. Shared by the real window and the snapshot
/// rendering so both show exactly the same views.
struct MainSectionContent: View {
    let selection: MainSection

    var body: some View {
        switch selection {
        case .overview:
            OverviewView()
        case .buttons:
            ButtonsSectionView()
        case .actions:
            ActionsSectionView()
        case .profiles:
            ProfilesView()
        case .scrolling:
            ScrollingView()
        case .advanced:
            AdvancedSectionView()
        case .permissions:
            PermissionsView()
        case .about:
            AboutView()
        }
    }
}

/// A plain two-column rendering of the main window, used only by `--snapshot`.
///
/// The real window is a `NavigationSplitView`. On macOS 26+ its sidebar is a
/// Liquid Glass portal layer, and `cacheDisplay` offscreen sees only the glass,
/// never the rows (a screen recording permission would be needed for the real
/// compositor). This view reuses `MainSidebar` and `MainSectionContent` in an
/// ordinary hosting window so a snapshot can show every section and the
/// sidebar's real contents.
struct MainWindowSnapshotView: View {
    @EnvironmentObject private var windows: MainWindowState

    var body: some View {
        HStack(spacing: 0) {
            MainSidebar(selection: $windows.selection)
                .listStyle(.inset)
                .frame(width: 210)
            Divider()
            MainSectionContent(selection: windows.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The window's default size; wide enough that the tester pane's 860pt
        // minimum fits beside the 210pt sidebar without clipping.
        .frame(width: 1080, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
    }
}

/// The old Settings *Mouse* and *Buttons* tabs, unchanged, in the Buttons
/// section. The pane selection is local so the mouse diagram can still jump to
/// the buttons list when a control has two bindings (callout 8).
///
/// This is an explicit segmented control rather than a `TabView`: on macOS 26 a
/// tab strip is a glass element that does not draw in an offscreen snapshot, and
/// the Advanced section above is segmented too, so the two read the same way.
struct ButtonsSectionView: View {
    @State private var tab: SettingsTab = .mouse

    var body: some View {
        VStack(spacing: 0) {
            Picker("Pane", selection: $tab) {
                Label("Mouse", systemImage: "computermouse")
                    .tag(SettingsTab.mouse)
                Label("Buttons", systemImage: "list.bullet")
                    .tag(SettingsTab.buttons)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            switch tab {
            case .mouse:
                MouseSettingsView(selection: $tab)
            case .buttons, .permissions, .about:
                ButtonsSettingsView()
            }
        }
    }
}

/// The old Button Tester and Diagnostics windows, as two panes of one section.
struct AdvancedSectionView: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var windows: MainWindowState

    var body: some View {
        VStack(spacing: 0) {
            Picker("Pane", selection: $windows.advancedPane) {
                ForEach(AdvancedPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbolName)
                        .tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            pane
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch windows.advancedPane {
        case .tester:
            testerPane
        case .diagnostics:
            DiagnosticsView()
        }
    }

    @ViewBuilder
    private var testerPane: some View {
        if let tester = WindowManager.shared.tester {
            TesterView(tester: tester, actions: actions(for:))
                .onAppear { tester.start() }
                .onDisappear { tester.stop() }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The actions behind a callout, the same mapping the old tester window used.
    private func actions(for control: MouseControl) -> [MouseAction] {
        if let button = control.hidButtons.first {
            return [config.binding(for: button).action]
        }
        return config.shortcutBindings
            .filter { MouseMap.control(forShortcut: $0)?.number == control.number }
            .map(\.action)
    }
}

/// Overview: what the app is doing right now, at a glance. New work in this
/// track; the other sections are the existing views moved across unchanged.
struct OverviewView: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var eventTap: EventTapService
    @EnvironmentObject private var activeApp: ActiveAppMonitor
    @EnvironmentObject private var windows: MainWindowState
    @AppStorage(AppPreferences.keepInDock) private var keepInDock = false

    private var boundControlCount: Int {
        let buttons = config.config.bindings.filter { $0.action.isBound }.count
        let shortcuts = config.shortcutBindings.filter { $0.action.isBound }.count
        return buttons + shortcuts
    }

    private var totalControls: Int { MouseMap.controls.count }

    /// The profile the tap will use for the next event, so a per-app override
    /// is never silent. The monitor updates on app activation; no polling.
    private var profileSummary: String {
        guard let profile = config.config.profile(forBundleIdentifier: activeApp.frontmostBundleID) else {
            return "Profile: Default"
        }
        let count = profile.overrideCount
        return "Profile: \(profile.name) · \(count) override\(count == 1 ? "" : "s")"
    }

    var body: some View {
        // Re-read the non-observable HID listener state every couple of seconds
        // so a receiver that is plugged in or granted access shows up without a
        // relaunch.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Citlla E510")
                            .font(.largeTitle.bold())
                        Text("The mouse's controls at a glance. Remapping runs in the background whether or not this window is open.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    deviceCard
                    remappingCard
                    permissionsCard
                    bindingsCard
                    dockCard
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Cards

    private var deviceCard: some View {
        GroupBox("Device") {
            VStack(alignment: .leading, spacing: 10) {
                statusRow(
                    title: "Event tap",
                    detail: eventTap.isRunning ? "Active" : (eventTap.lastError ?? "Inactive"),
                    ok: eventTap.isRunning
                )

                Divider()

                ForEach(MouseReceiver.known) { receiver in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(receiver.name)
                        Spacer(minLength: 12)
                        Text(receiver.idDescription)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                statusRow(title: "Mouse HID listener", detail: hidListenerStatus, ok: hidListenerIsRunning)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var remappingCard: some View {
        GroupBox("Remapping") {
            HStack(spacing: 12) {
                Toggle(
                    "Enable remapping",
                    isOn: Binding(
                        get: { config.config.enabled },
                        set: { newValue in
                            config.config.enabled = newValue
                            if newValue { eventTap.startIfNeeded() }
                        }
                    )
                )
                Spacer(minLength: 12)
                Text(config.config.enabled ? "Buttons are being remapped" : "Every button behaves normally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private var permissionsCard: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 10) {
                permissionRow(
                    "Accessibility",
                    detail: "Needed to intercept and replace mouse buttons",
                    granted: PermissionManager.hasAccessibility
                )
                permissionRow(
                    "Input Monitoring",
                    detail: "Needed to recognise the mouse's thumb buttons",
                    granted: PermissionManager.hasInputMonitoring
                )
                HStack {
                    Spacer()
                    Button("Review Permissions…") { windows.selection = .permissions }
                        .controlSize(.small)
                }
            }
            .padding(4)
        }
    }

    private var bindingsCard: some View {
        GroupBox("Bindings") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(boundControlCount) of \(totalControls) controls bound")
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(profileSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(
                    value: Double(boundControlCount),
                    total: Double(max(totalControls, 1))
                )
            }
            .padding(4)
        }
    }

    private var dockCard: some View {
        GroupBox("Dock") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Keep in Dock", isOn: $keepInDock)
                    .onChange(of: keepInDock) { _, newValue in
                        WindowManager.shared.setKeepInDock(newValue)
                    }
                Text("Off by default: the Dock icon and ⌘-Tab entry appear only while a window is open. On: Citlla E510 stays in the Dock, and clicking its icon opens this window. Remapping runs either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(4)
        }
    }

    // MARK: - Rows

    private func statusRow(title: String, detail: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer(minLength: 12)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(granted ? "Granted" : "Not granted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(granted ? Color.green : Color.orange)
        }
    }

    // MARK: - Live HID listener

    private var hidListenerIsRunning: Bool {
        WindowManager.shared.tagger?.isRunning ?? false
    }

    private var hidListenerStatus: String {
        guard let tagger = WindowManager.shared.tagger else { return "Unavailable" }
        if tagger.isRunning {
            let count = tagger.deviceCount
            return "Running · \(count) interface\(count == 1 ? "" : "s")"
        }
        if !PermissionManager.hasInputMonitoring {
            return "Waiting for Input Monitoring"
        }
        return "Waiting for the receiver"
    }
}
