import AppKit
import SwiftUI

/// The Actions section: every control that has an action, what it runs, and the
/// two compound kinds — chord clicks and sequences — in full.
///
/// The Buttons section is organised around the mouse diagram, which is the right
/// shape for "what does this button do". This section is the other direction:
/// one flat list of what is actually assigned, so a long sequence or a chord is
/// visible without opening each control, and a filter answers "which controls are
/// chained?" without reading every row.
struct ActionsSectionView: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var windows: MainWindowState

    @State private var filter: Filter = .all
    @State private var editing: ActionEditorSheet.Target?

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case chords
        case sequences

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .chords: "Chords"
            case .sequences: "Sequences"
            }
        }
    }

    /// One assigned action, with the control it belongs to.
    private struct Row: Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let action: MouseAction
        let target: ActionEditorSheet.Target
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            rowView(row)
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { target in
            ActionEditorSheet(target: target)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Actions")
                .font(.largeTitle.bold())
            Text(assignedSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var assignedSummary: String {
        let bound = allRows.count
        let total = MouseMap.controls.count
        return "\(bound) of \(total) controls have an action. Chords and sequences are built in the editor, and a sequence can run up to \(SequenceLimits.maxSteps) steps."
    }

    // MARK: - Rows

    /// Every assigned action, in control order: the mouse's buttons first, then
    /// the keys its thumb controls send.
    private var allRows: [Row] {
        let buttons = config.config.bindings
            .sorted { $0.button < $1.button }
            .filter { $0.action.isBound }
            .map { binding in
                Row(
                    id: "button-\(binding.button)",
                    name: binding.name,
                    subtitle: binding.subtitle,
                    action: binding.action,
                    target: .button(binding)
                )
            }

        let keys = config.shortcutBindings
            .filter { $0.action.isBound }
            .map { binding in
                Row(
                    id: "shortcut-\(binding.id)",
                    name: binding.name,
                    subtitle: binding.subtitle,
                    action: binding.action,
                    target: .shortcut(binding)
                )
            }

        return buttons + keys
    }

    private var rows: [Row] {
        allRows.filter { row in
            switch filter {
            case .all:
                true
            case .chords:
                row.action.kind == .mouseClick && row.action.clickModifiers != 0
            case .sequences:
                row.action.kind == .sequence
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: row.action.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(row.action.isBound ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 22)
                .padding(.leading, 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body.weight(.medium))
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.action.summary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = detail(for: row.action) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 320, alignment: .trailing)

            Button("Edit") { editing = row.target }
                .controlSize(.small)
                .padding(.trailing, 20)
        }
        .padding(.vertical, 10)
    }

    /// The second line: how a chord is composed, or how long a sequence is.
    /// A plain action needs none — `summary` already says everything.
    private func detail(for action: MouseAction) -> String? {
        switch action.kind {
        case .sequence:
            let steps = action.steps.normalized()
            let delay = steps.reduce(0) { $0 + $1.clampedDelay }
            return "\(steps.count) step\(steps.count == 1 ? "" : "s") · \(delay) ms of waits"
        case .mouseClick where action.clickModifiers != 0:
            return "Holds the modifiers down around the click"
        default:
            return nil
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptySymbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.title3.weight(.semibold))
            Text(emptyDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Open Buttons") { windows.selection = .buttons }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptySymbol: String {
        switch filter {
        case .all: "list.bullet"
        case .chords: "command"
        case .sequences: "list.number"
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "Nothing is assigned yet"
        case .chords: "No chord clicks"
        case .sequences: "No sequences"
        }
    }

    private var emptyDetail: String {
        switch filter {
        case .all:
            "Every button and thumb key still does what it normally does. Assign an action from the Buttons section."
        case .chords:
            "A chord holds ⌃⌥⇧⌘ around a click, so a middle click can be a ⌘-click or an ⌥-click. Add one from any Mouse Click action."
        case .sequences:
            "A sequence fires up to \(SequenceLimits.maxSteps) steps with a short wait between them, so one press can copy and paste, or open an app and run a shortcut in it."
        }
    }
}
