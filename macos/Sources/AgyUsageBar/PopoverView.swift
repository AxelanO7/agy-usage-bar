import SwiftUI

struct PopoverView: View {
    @ObservedObject var m: UsageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let banner = m.banner { BannerView(text: banner) }
            if let snap = m.snapshot, let group = m.selectedGroup(in: snap) {
                if snap.groups.count > 1 {
                    PoolPicker(groups: snap.groups, selected: group.id) { m.poolID = $0 }
                }
                if let five = group.five {
                    HeroCard(bucket: five, projection: m.projection(for: five), trend: m.trend(for: five),
                             now: m.now, pinned: m.isPinned(five))
                }
                if let weekly = group.weekly {
                    WeeklyCard(bucket: weekly, now: m.now, pinned: m.isPinned(weekly))
                }
            } else if m.banner == nil {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.padding(.vertical, 40)
            }
            Text(L.source).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Antigravity").font(.system(size: 16, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { m.refresh() } label: {
                ZStack {
                    IconLabel(symbol: "arrow.clockwise").opacity(m.isRefreshing ? 0 : 1)
                    if m.isRefreshing { ProgressView().controlSize(.small) }
                }
            }
            .buttonStyle(.plain)
            .disabled(m.isRefreshing)
            .help(L.refreshNow)
            Menu {
                Picker(L.showInMenuBar, selection: $m.choice) {
                    ForEach(DisplayChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                Toggle(L.showCountdown, isOn: $m.showCountdown)
                Divider()
                Picker(L.languageMenu, selection: $m.langOverride) {
                    Text(L.languageAuto).tag("auto")
                    Text("English").tag("en")
                    Text("Bahasa Indonesia").tag("id")
                }
                Toggle(L.launchAtLogin, isOn: Binding(get: { m.launchAtLogin }, set: { m.setLaunchAtLogin($0) }))
                Divider()
                Button(L.quit) { NSApp.terminate(nil) }
            } label: {
                IconLabel(symbol: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L.settings)
        }
    }

    private var statusColor: Color {
        switch m.state {
        case .ok: return .green
        case .idle, .loading: return .orange
        default: return .red
        }
    }

    private var subtitle: String {
        guard let s = m.snapshot else { return L.loading }
        return L.updated(Fmt.clock(s.fetchedAt))
    }
}

private struct HeroCard: View {
    let bucket: Bucket
    let projection: Projection?
    let trend: Trend?
    let now: Date
    let pinned: Bool

    var body: some View {
        let color = bucket.band.color
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    RingGauge(used: bucket.used, color: color)
                    VStack(spacing: 1) {
                        Text("\(bucket.usedPercent)%")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(color)
                            .minimumScaleFactor(0.7)
                        Caption(text: L.used)
                    }
                }
                .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Caption(text: L.fiveHourCaption)
                        if pinned { PinMark() }
                    }
                    if bucket.untouched {
                        Text(L.notUsedYet).font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text(L.windowStartsHint)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(Fmt.countdown(bucket.resetTime.timeIntervalSince(now)))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(L.untilReset).font(.system(size: 12)).foregroundStyle(.secondary)
                        paceLine.padding(.top, 3)
                    }
                }
                Spacer(minLength: 0)
            }

            if let trend {
                VStack(spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .trailing) {
                            Text("100%"); Spacer(); Text("0")
                        }
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                        .frame(width: 26, height: 60)
                        TrendChart(trend: trend, color: trendColor).frame(height: 60)
                    }
                    HStack {
                        Text(L.started(Fmt.clock(trend.start)))
                        Spacer()
                        if trend.forecast != nil { ForecastKey(color: trendColor) }
                        Spacer()
                        Text(L.resetsShort(Fmt.clock(trend.end)))
                    }
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(.leading, 32)
                }
            }
        }
        .card()
    }

    private var trendColor: Color {
        if case .exhaust? = projection?.pace { return .orange }
        return bucket.band.color
    }

    @ViewBuilder private var paceLine: some View {
        switch projection?.pace {
        case .exhaust(let eta)?:
            Label { Text(L.runsOut(Fmt.countdown(eta))) } icon: { Image(systemName: "flame.fill") }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
        case .safe?:
            Label { Text(L.lastsUntilReset) } icon: { Image(systemName: "checkmark.circle.fill") }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }
}

private struct WeeklyCard: View {
    let bucket: Bucket
    let now: Date
    let pinned: Bool

    var body: some View {
        let color = bucket.band.color
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Caption(text: L.weeklyCaption)
                    if pinned { PinMark() }
                }
                Spacer()
                Text(bucket.untouched ? L.notUsedShort : "\(bucket.usedPercent)%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(bucket.untouched ? Color.secondary : color)
            }
            BarGauge(used: bucket.used, color: color, tick: bucket.untouched ? nil : bucket.elapsed(at: now))
            HStack {
                Text(bucket.untouched ? L.windowStartsHint : L.resets(Fmt.weekdayClock(bucket.resetTime)))
                Spacer()
                if let p = bucket.pacing(at: now) { Text(p.label).foregroundStyle(p.color) }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .card()
    }
}
