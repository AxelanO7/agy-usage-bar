import AppKit
import SwiftUI

extension Band {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warn: return .orange
        case .hot: return .red
        }
    }
    var nsColor: NSColor {
        switch self {
        case .ok: return .systemGreen
        case .warn: return .systemOrange
        case .hot: return .systemRed
        }
    }
}

extension Pacing {
    var label: String {
        switch self {
        case .under: return L.underPace
        case .even: return L.onPace
        case .over: return L.overPace
        }
    }
    var color: Color {
        switch self {
        case .under: return .green
        case .even: return .secondary
        case .over: return .orange
        }
    }
}

/// What the menu bar item shows: an optional ring, a short text, and a tooltip.
struct BarState: Equatable {
    var text: String
    var fraction: Double?
    var band: Band
    var symbol: String?
    var tooltip: String
}

enum Fmt {
    /// 6d 12h · 4h 52m · 7m · <1m   (Indonesian: 6hr 12j · 4j 52m)
    static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        let (du, hu, mu) = (L.dayUnit, L.hourUnit, L.minuteUnit)
        if d > 0 { return h > 0 ? "\(d)\(du) \(h)\(hu)" : "\(d)\(du)" }
        if h > 0 { return m > 0 ? "\(h)\(hu) \(m)\(mu)" : "\(h)\(hu)" }
        if m > 0 { return "\(m)\(mu)" }
        return "<1m"
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "Sat 07:07" / "Sab 07:07"
    static func weekdayClock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L.lang == .id ? "id_ID" : "en_US")
        f.dateFormat = "EEE HH:mm"
        return f.string(from: date)
    }

    static func chosenBucket(_ snap: Snapshot, _ choice: DisplayChoice) -> Bucket? {
        if let id = choice.bucketID, let b = snap.bucket(id: id) { return b }
        return snap.allBuckets.max { $0.used < $1.used }   // ties -> the first one (5-hour)
    }

    /// "72% · 2h 10m"   weekly: "41% wk · 2d 5h"   not started: "0%"
    static func barText(bucket b: Bucket, showCountdown: Bool, now: Date) -> String {
        var t = "\(b.usedPercent)%"
        if !b.isFiveHour { t += " \(L.weekTag)" }
        if showCountdown && !b.untouched { t += " · \(countdown(b.resetTime.timeIntervalSince(now)))" }
        return t
    }

    static func tooltip(snapshot: Snapshot, bucket b: Bucket, now: Date) -> String {
        let pool = snapshot.groups.first { $0.buckets.contains(b) }?.shortName ?? ""
        return L.tooltip(pool: pool, window: b.windowLabel, percent: b.usedPercent,
                         reset: b.untouched ? nil : countdown(b.resetTime.timeIntervalSince(now)))
    }
}
