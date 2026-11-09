import LighthouseKit
import SwiftUI

/// The small mono line above headings.
struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11))
            .tracking(0.8)
            .foregroundStyle(Theme.ink3)
    }
}

/// A section title with an optional count.
struct SectionTitle: View {
    let text: String
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text.uppercased())
                .font(Theme.display(13))
                .tracking(0.6)
                .foregroundStyle(Theme.ink2)
            if let count { Text("\(count)").font(Theme.mono(11)).foregroundStyle(Theme.ink3) }
            Spacer()
        }
        .padding(.top, 10)
    }
}

/// A status dot.
struct Dot: View {
    let color: Color
    var hollow = false

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: hollow ? 1.5 : 0)
            .background(Circle().fill(hollow ? Color.clear : color))
            .frame(width: 8, height: 8)
    }
}

/// A small mono label, such as the source of an item.
struct Tag: View {
    let text: String
    var highlighted = false

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(10.5, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                highlighted ? Theme.lampSoft : Theme.surface3,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .foregroundStyle(highlighted ? Theme.lampInk : Theme.ink2)
    }
}

/// A status pill. Calm states stay quiet, only what needs attention has color.
struct Pill: View {
    let status: String

    private var colors: (Color, Color) {
        switch status {
        case "waiting", "pending": (Theme.lampSoft, Theme.lampInk)
        case "running": (Theme.infoSoft, Theme.info)
        case "failed", "rejected", "denied", "limit_exceeded", "expired":
            (Theme.critSoft, Theme.crit)
        default: (.clear, Theme.ink3)
        }
    }

    var body: some View {
        Text(statusName(status))
            .font(Theme.body(11.5, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(colors.0, in: Capsule())
            .foregroundStyle(colors.1)
    }
}

/// A surface with a hairline border.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
    }
}

/// A row with the colored edge that says what kind of item it is.
struct EdgeRow<Content: View>: View {
    let edge: Color
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.vertical, 12)
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 4) }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
    }
}

/// The filled button for the main action.
struct LampButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.lamp, in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(Theme.onLamp)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.8 : 1)
    }
}

/// The outlined button for everything else.
struct QuietButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
            .foregroundStyle(destructive ? Theme.crit : Theme.ink)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}

/// The mark: a lightning bolt.
struct LogoMark: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / 24
            let points: [(CGFloat, CGFloat)] = [(15.6, 2), (7.8, 13.6), (11.8, 13.6), (9.6, 22), (16.6, 10), (12.8, 10)]
            var bolt = Path()
            bolt.addLines(points.map { CGPoint(x: $0.0 * unit, y: $0.1 * unit) })
            bolt.closeSubpath()
            context.fill(bolt, with: .color(Theme.ink))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The page background used behind cards.
    func pageBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
