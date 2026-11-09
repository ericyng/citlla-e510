import AppKit
import SwiftUI

/// The numbered badge from the manufacturer's diagram: a blue disc with a white
/// numeral. Redrawn rather than cropped so it stays sharp at any size.
struct MouseControlBadge: View {
    let number: Int
    var active: Bool = false
    var muted: Bool = false

    static let blue = Color(red: 0 / 255, green: 117 / 255, blue: 249 / 255)

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            Circle()
                .strokeBorder(.white.opacity(0.85), lineWidth: 1.2)
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: 23, height: 23)
        .shadow(color: active ? Self.blue.opacity(0.55) : .clear, radius: 6)
        .scaleEffect(active ? 1.15 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: active)
    }

    private var fill: Color {
        if muted { return Color.secondary.opacity(0.35) }
        return active ? Color.accentColor : Self.blue
    }
}

/// The two renders lifted out of the diagram, on a light card so the dark
/// mouse reads in both appearances.
struct MouseRenderPair: View {
    var height: CGFloat = 240
    var spacing: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            panel(image: "MouseTop", caption: "Top", aspect: 485.0 / 727.0)
            panel(image: "MouseSide", caption: "Side", aspect: 320.0 / 753.0)
        }
    }

    private func panel(image: String, caption: String, aspect: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .frame(width: height * aspect)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.99), Color(white: 0.90)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                )
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// The nine callouts as a list. In Settings each row opens the binding behind
/// it; in the tester each row reports what the physical control actually sent.
struct MouseControlLegend: View {
    var actions: (MouseControl) -> [MouseAction] = { _ in [] }
    var detection: (MouseControl) -> String? = { _ in nil }
    var highlighted: Set<Int> = []
    var onSelect: ((MouseControl) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MouseMap.controls) { control in
                row(for: control)
                if control.number != MouseMap.controls.last?.number {
                    Divider().padding(.leading, 35)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for control: MouseControl) -> some View {
        let bound = actions(control)
        let detected = detection(control)
        let row = HStack(alignment: .top, spacing: 12) {
            MouseControlBadge(
                number: control.number,
                active: highlighted.contains(control.number),
                muted: !control.isRemappable
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(control.title)
                    .font(.callout.weight(.medium))
                Text(detected ?? control.note)
                    .font(.caption)
                    .foregroundStyle(detected == nil ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !bound.isEmpty {
                HStack(spacing: 6) {
                    Text(bound.map(\.summary).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(bound.contains(where: \.isBound) ? .primary : .secondary)
                        .lineLimit(1)
                    if onSelect != nil, control.isRemappable {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())

        if let onSelect, control.isRemappable {
            Button { onSelect(control) } label: { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }
}
