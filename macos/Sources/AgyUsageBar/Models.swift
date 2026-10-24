import Foundation

/// Satu jendela kuota (mis. "gemini-5h"). `remaining` 0...1 persis seperti `remaining_fraction` dari agy.
struct Bucket: Codable, Equatable, Identifiable {
    let id: String
    let window: String          // "5h" | "weekly"
    let remaining: Double
    let resetTime: Date

    var isFiveHour: Bool { window == "5h" }
    var used: Double { min(max(1 - remaining, 0), 1) }
    var usedPercent: Int { Int((used * 100).rounded()) }
    /// Jendela belum dimulai: agy mengisi reset_time = sekarang + jendela, jadi hitung mundurnya palsu.
    var untouched: Bool { remaining >= 0.9999 }
    var windowLabel: String { isFiveHour ? L.fiveHourName : L.weeklyName }

    var windowLength: TimeInterval { isFiveHour ? 5 * 3600 : 7 * 86400 }
    /// Window start = reset - length (only meaningful once the window has started, i.e. not `untouched`).
    var windowStart: Date { resetTime.addingTimeInterval(-windowLength) }
    func elapsed(at now: Date) -> Double { min(max(now.timeIntervalSince(windowStart) / windowLength, 0), 1) }
    var band: Band { Band(percent: usedPercent) }

    /// Compares consumption with a perfectly even burn over the window.
    func pacing(at now: Date) -> Pacing? {
        guard !untouched else { return nil }
        let e = elapsed(at: now)
        if used < e * 0.85 { return .under }
        if used > e * 1.15 + 0.01 { return .over }
        return .even
    }
}

enum Pacing: Equatable { case under, even, over }

enum Band: Equatable {
    case ok, warn, hot
    /// Same bands as the reference app: green 0-60, amber 61-85, red 86-100 (percent used).
    init(percent: Int) { self = percent <= 60 ? .ok : (percent <= 85 ? .warn : .hot) }
}

struct UsageGroup: Codable, Equatable, Identifiable {
    let name: String
    let models: String
    let buckets: [Bucket]
    var id: String { name }

    var five: Bucket? { buckets.first { $0.isFiveHour } }
    var weekly: Bucket? { buckets.first { !$0.isFiveHour } }
    var worstUsed: Double { buckets.map(\.used).max() ?? 0 }
    var idle: Bool { buckets.allSatisfy(\.untouched) }
    /// "Gemini" / "Claude & GPT" for the two known pools, otherwise the name agy reports.
    var shortName: String {
        let key = buckets.first?.id ?? ""
        if key.hasPrefix("gemini") { return "Gemini" }
        if key.hasPrefix("3p") { return "Claude & GPT" }
        return name
    }
}

struct Snapshot: Codable, Equatable {
    let fetchedAt: Date
    let groups: [UsageGroup]

    /// 5 jam dulu, baru mingguan, per grup. Urutan ini dipakai juga untuk memilih yang "tertinggi" saat seri.
    var allBuckets: [Bucket] {
        groups.flatMap { $0.buckets.sorted { $0.isFiveHour && !$1.isFiveHour } }
    }
    func bucket(id: String) -> Bucket? { allBuckets.first { $0.id == id } }
}

enum FetchError: Error, Equatable {
    case noAgy
    case notSignedIn
    case failed(String)
}

enum DisplayChoice: String, CaseIterable, Identifiable {
    case gemini5h, geminiWeekly, thirdParty5h, thirdPartyWeekly, highest
    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini5h: return L.choiceGemini5h
        case .geminiWeekly: return L.choiceGeminiWeekly
        case .thirdParty5h: return L.choiceThirdParty5h
        case .thirdPartyWeekly: return L.choiceThirdPartyWeekly
        case .highest: return L.choiceHighest
        }
    }

    var bucketID: String? {
        switch self {
        case .gemini5h: return "gemini-5h"
        case .geminiWeekly: return "gemini-weekly"
        case .thirdParty5h: return "3p-5h"
        case .thirdPartyWeekly: return "3p-weekly"
        case .highest: return nil
        }
    }
}

enum UsageParser {
    private struct Raw: Decodable {
        struct Command: Decodable { let data: DataBlock? }
        struct DataBlock: Decodable { let groups: [Group]? }
        struct Group: Decodable { let name: String; let description: String?; let buckets: [B]? }
        struct B: Decodable {
            let id: String
            let window: String?
            let remaining_fraction: Double?
            let reset_time: String?
        }
        let status: String?
        let response: String?
        let command: Command?
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> Snapshot {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
            throw classify(String(decoding: data.prefix(300), as: UTF8.self))
        }
        if let s = raw.status, s != "SUCCESS" { throw classify(raw.response ?? s) }
        guard let groups = raw.command?.data?.groups, !groups.isEmpty else {
            throw classify(raw.response ?? "")
        }
        let parsed = groups.map { g -> UsageGroup in
            let buckets = (g.buckets ?? []).compactMap { b -> Bucket? in
                guard let remaining = b.remaining_fraction else { return nil }
                let window = b.window ?? (b.id.hasSuffix("5h") ? "5h" : "weekly")
                let fallback = now.addingTimeInterval(window == "5h" ? 5 * 3600 : 7 * 86400)
                return Bucket(id: b.id, window: window, remaining: remaining, resetTime: date(b.reset_time) ?? fallback)
            }
            return UsageGroup(name: g.name, models: models(g.description), buckets: buckets)
        }
        guard parsed.contains(where: { !$0.buckets.isEmpty }) else { throw FetchError.failed(L.unreadable) }
        return Snapshot(fetchedAt: now, groups: parsed)
    }

    static func classify(_ text: String) -> FetchError {
        let t = text.lowercased()
        if ["sign in", "sign-in", "log in", "login", "authenticat", "unauthorized", "credential"].contains(where: t.contains) {
            return .notSignedIn
        }
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return .failed(first.isEmpty ? L.emptyOutput : String(first.prefix(120)))
    }

    private static func models(_ description: String?) -> String {
        guard let d = description else { return "" }
        let parts = d.split(separator: ":", maxSplits: 1)
        return String((parts.count == 2 ? parts[1] : parts[0]).trimmingCharacters(in: .whitespaces))
    }

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
