import SwiftUI

extension View {
    /// Rounded surface used for every block in the popover.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

struct Caption: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).kerning(0.9).foregroundStyle(.secondary)
    }
}

/// Dashed swatch + label used as the chart legend for the forecast line.
struct ForecastKey: View {
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 16, y: 1)) }
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [3, 3]))
                .frame(width: 16, height: 2)
            Text(L.forecast).foregroundStyle(color)
        }
    }
}

struct PinMark: View {
    var body: some View {
        Image(systemName: "menubar.rectangle")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .help(L.pinnedHelp)
    }
}

/// Circular gauge: faint track plus an arc that starts at 12 o'clock and fades in toward its head.
struct RingGauge: View {
    let used: Double
    let color: Color
    var lineWidth: CGFloat = 11

    var body: some View {
        let u = min(max(used, 0), 1)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            if u > 0 {
                Circle()
                    .trim(from: 0, to: max(u, 0.004))
                    .stroke(AngularGradient(gradient: Gradient(colors: [color.opacity(0.55), color]),
                                            center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(u, 0.01))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
    }
}

/// Horizontal gauge with an optional "even pace" tick (where an even burn would be by now).
struct BarGauge: View {
    let used: Double
    let color: Color
    var tick: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10)).frame(height: 8)
                if used > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, w * min(used, 1)), height: 8)
                }
                if let tick {
                    Capsule().fill(Color.primary.opacity(0.7)).frame(width: 2, height: 14)
                        .offset(x: min(max(w * tick - 1, 0), w - 2))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
    }
}

struct TrendChart: View {
    let trend: Trend
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pad: CGFloat = 4
            let h = geo.size.height - pad * 2
            let span = max(trend.end.timeIntervalSince(trend.start), 1)
            let x: (Date) -> CGFloat = { CGFloat($0.timeIntervalSince(trend.start) / span) * w }
            let y: (Double) -> CGFloat = { pad + h * (1 - CGFloat(min(max($0, 0), 1))) }
            ZStack {
                Path { p in
                    for g in [0.0, 0.5, 1.0] {
                        p.move(to: CGPoint(x: 0, y: y(g)))
                        p.addLine(to: CGPoint(x: w, y: y(g)))
                    }
                }
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                if let first = trend.points.first, let last = trend.points.last {
                    Path { p in
                        p.move(to: CGPoint(x: x(first.t), y: y(0)))
                        for pt in trend.points { p.addLine(to: CGPoint(x: x(pt.t), y: y(pt.used))) }
                        p.addLine(to: CGPoint(x: x(last.t), y: y(0)))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.30), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))

                    Path { p in
                        for (i, pt) in trend.points.enumerated() {
                            let c = CGPoint(x: x(pt.t), y: y(pt.used))
                            if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if let f = trend.forecast {
                        Path { p in
                            p.move(to: CGPoint(x: x(last.t), y: y(last.used)))
                            p.addLine(to: CGPoint(x: x(f.t), y: y(f.used)))
                        }
                        .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [4, 4]))
                    }
                    Circle().fill(color).frame(width: 8, height: 8).position(x: x(last.t), y: y(last.used))
                }
            }
        }
    }
}

/// Two-way switch between the model pools, each with a status dot.
struct PoolPicker: View {
    let groups: [UsageGroup]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(groups) { g in
                let isOn = g.id == selected
                Button { onSelect(g.id) } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(g.idle ? Color.secondary.opacity(0.5) : Band(percent: Int((g.worstUsed * 100).rounded())).color)
                            .frame(width: 7, height: 7)
                        Text(g.shortName).font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isOn ? Color.primary.opacity(0.12) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct IconLabel: View {
    let symbol: String
    @State private var hover = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.primary.opacity(hover ? 0.10 : 0)))
            .contentShape(Circle())
            .onHover { hover = $0 }
    }
}

struct BannerView: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.12)))
    }
}
