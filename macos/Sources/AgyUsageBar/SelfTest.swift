import Foundation

/// `AgyUsageBar --selftest`: parser, formatting, language, pace and trend checks without GUI or network.
enum SelfTest {
    private static let fixture = """
    {"conversation_id":"","status":"SUCCESS","response":"x","num_turns":0,"command":{"name":"usage","data":{"description":"d","groups":[
    {"name":"Gemini Models","description":"Models within this group: Gemini Flash, Gemini Pro","buckets":[
    {"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.9882386326789856,"reset_time":"2026-10-30T23:07:13Z"},
    {"id":"gemini-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.9860554933547974,"reset_time":"2026-10-24T14:59:51Z"}]},
    {"name":"Claude and GPT models","description":"Models within this group: Claude Opus, Claude Sonnet, GPT-OSS","buckets":[
    {"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":1,"reset_time":"2026-10-31T10:08:04Z"},
    {"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":1,"reset_time":"2026-10-24T15:08:04Z"}]}]}}}
    """

    static func run() -> Int32 {
        var passed = 0, failed = 0
        func check(_ ok: Bool, _ name: String) {
            if ok { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
        }
        func near(_ a: Double, _ b: Double, _ tol: Double = 1) -> Bool { abs(a - b) <= tol }

        L.lang = .en
        let now = UsageParser.date("2026-10-24T10:08:04Z")!
        let snap = try! UsageParser.parse(Data(fixture.utf8), now: now)

        // Parser and model
        check(snap.groups.count == 2 && snap.allBuckets.count == 4, "parse: 2 groups, 4 buckets")
        check(snap.groups[0].models == "Gemini Flash, Gemini Pro", "parse: model list")
        check(snap.allBuckets.first?.id == "gemini-5h", "order: 5-hour first")
        check(snap.bucket(id: "gemini-5h")?.usedPercent == 1, "gemini-5h used 1%")
        check(snap.bucket(id: "3p-5h")?.untouched == true, "3p-5h not started")
        check(snap.bucket(id: "gemini-5h")?.untouched == false, "gemini-5h started")
        check(snap.groups[0].shortName == "Gemini" && snap.groups[1].shortName == "Claude & GPT", "pool short names")
        check(snap.groups[0].idle == false && snap.groups[1].idle == true, "pool idle flag")
        check(UsageParser.date("2026-10-24T10:08:04.123Z") != nil, "fractional-second date")
        let g5 = snap.bucket(id: "gemini-5h")!
        let startedAgo = 493.0   // 18000 s window - 17507 s left
        check(near(g5.windowStart.timeIntervalSince(now), -startedAgo, 2), "window start = reset - 5h")
        check(g5.elapsed(at: now) > 0.02 && g5.elapsed(at: now) < 0.04, "elapsed fraction of the 5-hour window")

        // Menu bar text (English)
        func text(_ c: DisplayChoice, countdown: Bool = true) -> String {
            guard let b = Fmt.chosenBucket(snap, c) else { return "-" }
            return Fmt.barText(bucket: b, showCountdown: countdown, now: now)
        }
        check(text(.gemini5h) == "1% · 4h 51m", "text gemini5h = \(text(.gemini5h))")
        check(text(.geminiWeekly) == "1% wk · 6d 12h", "text geminiWeekly = \(text(.geminiWeekly))")
        check(text(.thirdParty5h) == "0%", "text not started = \(text(.thirdParty5h))")
        check(text(.thirdPartyWeekly) == "0% wk", "text weekly not started = \(text(.thirdPartyWeekly))")
        check(text(.highest) == "1% · 4h 51m", "text highest = \(text(.highest))")
        check(text(.gemini5h, countdown: false) == "1%", "text without countdown")

        // Indonesian
        L.lang = .id
        check(text(.gemini5h) == "1% · 4j 51m", "id text gemini5h = \(text(.gemini5h))")
        check(text(.geminiWeekly) == "1% mgg · 6hr 12j", "id text geminiWeekly = \(text(.geminiWeekly))")
        check(Fmt.countdown(86400) == "1hr" && Fmt.countdown(90000) == "1hr 1j", "id countdown days")
        L.lang = .en

        // Language detection
        check(L.detect(env: ["AGY_USAGE_LANG": "id"], preferred: ["en-US"]) == .id, "lang: env id wins")
        check(L.detect(env: ["AGY_USAGE_LANG": "en"], preferred: ["id-ID"]) == .en, "lang: env en wins")
        check(L.detect(env: [:], preferred: ["id-ID", "en"]) == .id, "lang: system id")
        check(L.detect(env: [:], preferred: ["en-US"]) == .en, "lang: system en")

        // Format
        check(Fmt.countdown(0) == "<1m" && Fmt.countdown(59) == "<1m", "countdown <1m")
        check(Fmt.countdown(60) == "1m" && Fmt.countdown(3600) == "1h", "countdown m/h")
        check(Fmt.countdown(3660) == "1h 1m" && Fmt.countdown(86400) == "1d", "countdown h m / d")
        check(Fmt.countdown(90000) == "1d 1h" && Fmt.countdown(-5) == "<1m", "countdown d h / negative")
        check(Band(percent: 60) == .ok && Band(percent: 61) == .warn && Band(percent: 85) == .warn && Band(percent: 86) == .hot, "bands")

        // Errors
        check((try? UsageParser.parse(Data("hello".utf8))) == nil, "garbage rejected")
        do { _ = try UsageParser.parse(Data("{\"status\":\"ERROR\",\"response\":\"Please sign in to continue\"}".utf8)); check(false, "not signed in") }
        catch { check((error as? FetchError) == .notSignedIn, "not signed in detected") }
        do { _ = try UsageParser.parse(Data("{\"status\":\"ERROR\",\"response\":\"boom\\nmore\"}".utf8)); check(false, "generic error") }
        catch { check((error as? FetchError) == .failed("boom"), "generic error = first line") }

        // Pacing against an even burn (weekly window, 6 of 7 days left -> 14.3% elapsed)
        func weekly(_ used: Double) -> Bucket {
            Bucket(id: "gemini-weekly", window: "weekly", remaining: 1 - used, resetTime: now.addingTimeInterval(6 * 86400))
        }
        check(weekly(0.05).pacing(at: now) == .under, "pacing under")
        check(weekly(0.14).pacing(at: now) == .even, "pacing even")
        check(weekly(0.30).pacing(at: now) == .over, "pacing over")
        check(weekly(0).pacing(at: now) == nil, "pacing nil when not started")

        // History + projection + trend
        func bucket(used: Double, resetIn: TimeInterval, five: Bool = true) -> Bucket {
            Bucket(id: "gemini-5h", window: five ? "5h" : "weekly", remaining: 1 - used, resetTime: now.addingTimeInterval(resetIn))
        }
        func hist(_ pts: [(TimeInterval, Double)]) -> History {
            var h = History()
            for (ago, used) in pts {
                let s = Snapshot(fetchedAt: now.addingTimeInterval(-ago), groups: [UsageGroup(name: "g", models: "", buckets: [bucket(used: used, resetIn: 3 * 3600)])])
                h.append(s)
            }
            return h
        }
        let rising = hist([(3600.0, 0.3), (1800.0, 0.4)])
        if case .exhaust(let eta)? = rising.pace(for: bucket(used: 0.5, resetIn: 3 * 3600), now: now) {
            check(near(eta, 9000), "pace: runs out in 2.5 h (\(eta))")
        } else { check(false, "pace: expected exhaust") }
        check(rising.pace(for: bucket(used: 0.5, resetIn: 3600), now: now) == .safe, "pace: safe if reset comes first")
        check(hist([(3600.0, 0.5), (1800.0, 0.5)]).pace(for: bucket(used: 0.5, resetIn: 3600), now: now) == nil, "pace: flat = none")
        check(hist([(300.0, 0.4)]).pace(for: bucket(used: 0.5, resetIn: 3600), now: now) == nil, "pace: span too short")
        let reset = hist([(4800.0, 0.9), (4200.0, 0.95), (3600.0, 0.05), (1800.0, 0.1)])
        if case .exhaust(let eta)? = reset.pace(for: bucket(used: 0.2, resetIn: 6 * 3600), now: now) {
            check(near(eta, 19200), "pace: cut at the reset (\(eta))")
        } else { check(false, "pace: expected cut at reset") }
        let decay = hist([(3600.0, 0.30), (1800.0, 0.299)])
        if case .exhaust(let eta)? = decay.pace(for: bucket(used: 0.5, resetIn: 3 * 3600), now: now) {
            check(near(eta, 9000), "pace: small decay does not cut (\(eta))")
        } else { check(false, "pace: small decay should still count") }

        let b5 = bucket(used: 0.5, resetIn: 3 * 3600)     // window started 2 h ago
        let proj = rising.projection(for: b5, now: now)
        if let t = rising.trend(for: b5, now: now, projection: proj) {
            check(t.points.count == 3 && t.points.last?.used == 0.5, "trend: 2 samples + now")
            check(near(t.start.timeIntervalSince(now), -2 * 3600) && near(t.end.timeIntervalSince(now), 3 * 3600), "trend: window bounds")
            check(near(t.forecast?.t.timeIntervalSince(now) ?? 0, 9000) && near(t.forecast?.used ?? 0, 1.0, 0.001), "trend: forecast reaches 100%")
        } else { check(false, "trend: expected data") }
        check(hist([(10800.0, 0.1)]).trend(for: b5, now: now, projection: nil) == nil, "trend: nothing for samples before the window")
        check(rising.trend(for: bucket(used: 0.5, resetIn: 3 * 3600, five: false), now: now, projection: nil) == nil, "trend: weekly has none")
        check(rising.trend(for: bucket(used: 0, resetIn: 5 * 3600), now: now, projection: nil) == nil, "trend: none when not started")

        var h = History()
        let mk = { (t: TimeInterval) in Snapshot(fetchedAt: now.addingTimeInterval(t), groups: snap.groups) }
        h.append(mk(0)); h.append(mk(180))
        check(h.samples.count == 4, "history: unchanged adds nothing (\(h.samples.count))")
        h.append(mk(16 * 60))
        check(h.samples.count == 8, "history: 15-minute heartbeat (\(h.samples.count))")
        h.append(mk(8 * 86400))
        check(h.samples.allSatisfy { $0.t >= now.addingTimeInterval(86400) }, "history: drops entries older than 7 days")

        print("selftest: \(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}
