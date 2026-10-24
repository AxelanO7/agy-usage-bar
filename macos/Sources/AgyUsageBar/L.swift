import Foundation

enum Lang: String {
    case en, id
}

/// UI strings in English and Indonesian. The language follows the system unless overridden
/// (menu, or the AGY_USAGE_LANG=en|id environment variable).
enum L {
    static var lang: Lang = detect()

    static func detect(env: [String: String] = ProcessInfo.processInfo.environment,
                       preferred: [String] = Locale.preferredLanguages) -> Lang {
        if let o = env["AGY_USAGE_LANG"]?.lowercased(), !o.isEmpty { return o.hasPrefix("id") ? .id : .en }
        return preferred.first?.lowercased().hasPrefix("id") == true ? .id : .en
    }

    private static func t(_ en: String, _ id: String) -> String { lang == .id ? id : en }

    // Time units used by Fmt.countdown: 6d 12h / 4h 52m   |   6hr 12j / 4j 52m
    static var dayUnit: String { t("d", "hr") }
    static var hourUnit: String { t("h", "j") }
    static var minuteUnit: String { "m" }
    static var weekTag: String { t("wk", "mgg") }

    // Popover
    static var fiveHourCaption: String { t("5-HOUR LIMIT", "BATAS 5 JAM") }
    static var weeklyCaption: String { t("WEEKLY LIMIT", "BATAS MINGGUAN") }
    static var used: String { t("USED", "TERPAKAI") }
    static var untilReset: String { t("until reset", "hingga reset") }
    static var notUsedYet: String { t("Not used yet", "Belum dipakai") }
    static var notUsedShort: String { t("Idle", "Belum") }
    static var windowStartsHint: String { t("The window starts with your next request", "Jendela mulai di permintaan berikutnya") }
    static func resets(_ when: String) -> String { t("Resets \(when)", "Reset \(when)") }
    static func updated(_ clock: String) -> String { t("Updated \(clock)", "Diperbarui \(clock)") }
    static var source: String { t("Source: agy -p /usage · no token, no model quota", "Sumber: agy -p /usage · tanpa token, tanpa kuota model") }
    static var loading: String { t("Loading…", "Memuat…") }
    static func runsOut(_ eta: String) -> String { t("Runs out in ~\(eta)", "Habis ±\(eta) lagi") }
    static var lastsUntilReset: String { t("Lasts until reset", "Cukup sampai reset") }
    static var underPace: String { t("Under pace", "Di bawah laju") }
    static var onPace: String { t("On pace", "Sesuai laju") }
    static var overPace: String { t("Over pace", "Di atas laju") }
    static func started(_ clock: String) -> String { t("Started \(clock)", "Mulai \(clock)") }
    static func resetsShort(_ clock: String) -> String { t("Resets \(clock)", "Reset \(clock)") }
    static var forecast: String { t("Forecast", "Perkiraan") }
    static var pinnedHelp: String { t("Shown in the menu bar", "Tampil di menu bar") }

    // Menu
    static var refreshNow: String { t("Refresh now", "Perbarui sekarang") }
    static var showInMenuBar: String { t("Show in menu bar", "Tampil di menu bar") }
    static var showCountdown: String { t("Show countdown", "Tampilkan hitung mundur") }
    static var languageMenu: String { t("Language", "Bahasa") }
    static var languageAuto: String { t("Automatic", "Otomatis") }
    static var launchAtLogin: String { t("Launch at login", "Buka saat login") }
    static var quit: String { t("Quit", "Keluar") }
    static var settings: String { t("Settings", "Pengaturan") }

    // Display choices
    static var choiceGemini5h: String { t("Gemini · 5-hour", "Gemini · 5 jam") }
    static var choiceGeminiWeekly: String { t("Gemini · weekly", "Gemini · mingguan") }
    static var choiceThirdParty5h: String { t("Claude & GPT · 5-hour", "Claude & GPT · 5 jam") }
    static var choiceThirdPartyWeekly: String { t("Claude & GPT · weekly", "Claude & GPT · mingguan") }
    static var choiceHighest: String { t("Highest (all)", "Tertinggi (semua)") }

    // Status / errors
    static var login: String { t("Sign in", "Login") }
    static func updateFailed(_ why: String) -> String { t("Update failed: \(why)", "Gagal memperbarui: \(why)") }
    static var notSignedIn: String { t("agy is not signed in. Run `agy` in a terminal and sign in first.", "agy belum login. Jalankan `agy` di terminal dan masuk dulu.") }
    static var noAgy: String { t("Can't find the agy command. Install agy or set AGY_PATH.", "Perintah agy tidak ditemukan. Pasang agy atau set AGY_PATH.") }
    static var unreadable: String { t("Unrecognized agy output", "Keluaran agy tidak dikenali") }
    static var emptyOutput: String { t("agy returned nothing", "Keluaran agy kosong") }
    static func timeout(_ seconds: Int) -> String { t("agy did not respond (timeout \(seconds)s)", "agy tidak merespons (timeout \(seconds) dtk)") }
    static func cannotRun(_ why: String) -> String { t("Could not run agy: \(why)", "Gagal menjalankan agy: \(why)") }

    // Tooltip
    static func tooltip(pool: String, window: String, percent: Int, reset: String?) -> String {
        let base = t("\(pool) · \(window): \(percent)% used", "\(pool) · \(window): \(percent)% terpakai")
        guard let reset else { return base }
        return base + t(", resets in \(reset)", ", reset \(reset) lagi")
    }
    static var fiveHourName: String { t("5-hour", "5 jam") }
    static var weeklyName: String { t("weekly", "mingguan") }
}
