import Foundation

struct Sample: Codable, Equatable {
    let t: Date
    let id: String
    let used: Double
}

enum Pace: Equatable {
    case exhaust(in: TimeInterval)   // at the current rate the limit runs out before the reset
    case safe
}

/// Burn rate (fraction of the limit per second) and what it means for this window.
struct Projection: Equatable {
    let rate: Double
    let pace: Pace
}

struct TrendPoint: Equatable {
    let t: Date
    let used: Double
}

/// Usage during the current window for the chart, plus the dashed forecast segment.
struct Trend: Equatable {
    let points: [TrendPoint]
    let start: Date
    let end: Date
    let forecast: TrendPoint?
}

/// Per-window usage history (max 7 days), used to estimate the burn rate and draw the trend chart.
struct History: Codable, Equatable {
    private(set) var samples: [Sample] = []
    static let keep: TimeInterval = 7 * 86400
    static let heartbeat: TimeInterval = 15 * 60
    /// agy can lower the used percentage slightly inside one window (old usage decays); only a drop this big counts as a reset.
    static let resetDrop = 0.02

    mutating func append(_ snap: Snapshot) {
        for b in snap.allBuckets {
            if let last = samples.last(where: { $0.id == b.id }),
               abs(last.used - b.used) < 1e-6,
               snap.fetchedAt.timeIntervalSince(last.t) < Self.heartbeat { continue }
            samples.append(Sample(t: snap.fetchedAt, id: b.id, used: b.used))
        }
        let cutoff = snap.fetchedAt.addingTimeInterval(-Self.keep)
        samples.removeAll { $0.t < cutoff }
    }

    /// Samples of one bucket since `from`, ending with the current reading, cut at the last sharp drop (a reset).
    private func recent(_ b: Bucket, from: Date, now: Date) -> [Sample] {
        var pts = samples
            .filter { $0.id == b.id && $0.t >= from && $0.t <= now }
            .sorted { $0.t < $1.t }
        pts.append(Sample(t: now, id: b.id, used: b.used))
        if let i = pts.indices.dropLast().last(where: { pts[$0].used - pts[$0 + 1].used > Self.resetDrop }) {
            pts = Array(pts[(i + 1)...])
        }
        return pts
    }

    /// Rate = rise in used fraction divided by time since the last reset inside the look-back.
    /// 5-hour: look back 90 min (min span 8 min); weekly: 24 h (min span 1 h).
    func projection(for b: Bucket, now: Date) -> Projection? {
        let lookback: TimeInterval = b.isFiveHour ? 90 * 60 : 24 * 3600
        let minSpan: TimeInterval = b.isFiveHour ? 8 * 60 : 3600
        let pts = recent(b, from: now.addingTimeInterval(-lookback), now: now)
        guard let first = pts.first else { return nil }
        let span = now.timeIntervalSince(first.t)
        guard span >= minSpan else { return nil }
        let delta = b.used - first.used
        guard delta > 0.0005 else { return nil }
        let rate = delta / span
        let eta = (1 - b.used) / rate
        return Projection(rate: rate, pace: now.addingTimeInterval(eta) < b.resetTime ? .exhaust(in: eta) : .safe)
    }

    func pace(for b: Bucket, now: Date) -> Pace? { projection(for: b, now: now)?.pace }

    /// Chart data for a started 5-hour window. Needs a few minutes of real samples; nothing is invented before the first one.
    func trend(for b: Bucket, now: Date, projection: Projection?) -> Trend? {
        guard b.isFiveHour, !b.untouched else { return nil }
        let pts = recent(b, from: b.windowStart, now: now)
        guard pts.count >= 2, let first = pts.first, now.timeIntervalSince(first.t) >= 5 * 60 else { return nil }
        var forecast: TrendPoint?
        if let p = projection {
            let horizon = min(b.resetTime.timeIntervalSince(now), (1 - b.used) / p.rate)
            if horizon > 60 {
                forecast = TrendPoint(t: now.addingTimeInterval(horizon), used: min(1, b.used + p.rate * horizon))
            }
        }
        return Trend(points: pts.map { TrendPoint(t: $0.t, used: $0.used) }, start: b.windowStart, end: b.resetTime, forecast: forecast)
    }
}

struct Store {
    let dir: URL

    static var defaultDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgyUsageBar", isDirectory: true)
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
    private var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }

    func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func write<T: Encodable>(_ value: T, _ name: String) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? encoder.encode(value) {
            try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
    }
}
