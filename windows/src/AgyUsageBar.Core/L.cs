namespace AgyUsageBar.Core;

public enum Lang { En, Id }

/// UI strings in English and Indonesian. The language follows the system unless overridden
/// (settings menu, or the AGY_USAGE_LANG=en|id environment variable).
public static class L
{
    public static Lang Current { get; set; } = Detect();

    public static Lang Detect(IDictionary<string, string?>? env = null, IReadOnlyList<string>? preferred = null)
    {
        var o = env is null
            ? Environment.GetEnvironmentVariable("AGY_USAGE_LANG")
            : env.TryGetValue("AGY_USAGE_LANG", out var v) ? v : null;
        if (!string.IsNullOrWhiteSpace(o)) return o.StartsWith("id", StringComparison.OrdinalIgnoreCase) ? Lang.Id : Lang.En;
        var first = preferred is { Count: > 0 } ? preferred[0] : System.Globalization.CultureInfo.CurrentUICulture.Name;
        return first.StartsWith("id", StringComparison.OrdinalIgnoreCase) ? Lang.Id : Lang.En;
    }

    private static string T(string en, string id) => Current == Lang.Id ? id : en;

    public static System.Globalization.CultureInfo Culture =>
        System.Globalization.CultureInfo.GetCultureInfo(Current == Lang.Id ? "id-ID" : "en-US");

    // Units used by Fmt.Countdown: 6d 12h / 4h 52m   |   6hr 12j / 4j 52m
    public static string DayUnit => T("d", "hr");
    public static string HourUnit => T("h", "j");
    public static string MinuteUnit => "m";
    public static string WeekTag => T("wk", "mgg");

    // Popup
    public static string FiveHourCaption => T("5-HOUR LIMIT", "BATAS 5 JAM");
    public static string WeeklyCaption => T("WEEKLY LIMIT", "BATAS MINGGUAN");
    public static string Used => T("USED", "TERPAKAI");
    public static string UntilReset => T("until reset", "hingga reset");
    public static string NotUsedYet => T("Not used yet", "Belum dipakai");
    public static string NotUsedShort => T("Idle", "Belum");
    public static string WindowStartsHint => T("The window starts with your next request", "Jendela mulai di permintaan berikutnya");
    public static string Resets(string when) => T($"Resets {when}", $"Reset {when}");
    public static string Updated(string clock) => T($"Updated {clock}", $"Diperbarui {clock}");
    public static string Source => T("Source: agy -p /usage · no token, no model quota", "Sumber: agy -p /usage · tanpa token, tanpa kuota model");
    public static string Loading => T("Loading…", "Memuat…");
    public static string RunsOut(string eta) => T($"Runs out in ~{eta}", $"Habis ±{eta} lagi");
    public static string LastsUntilReset => T("Lasts until reset", "Cukup sampai reset");
    public static string UnderPace => T("Under pace", "Di bawah laju");
    public static string OnPace => T("On pace", "Sesuai laju");
    public static string OverPace => T("Over pace", "Di atas laju");
    public static string Started(string clock) => T($"Started {clock}", $"Mulai {clock}");
    public static string ResetsShort(string clock) => T($"Resets {clock}", $"Reset {clock}");
    public static string Forecast => T("Forecast", "Perkiraan");
    public static string PinnedHelp => T("Shown in the tray icon", "Tampil di ikon tray");

    // Menu
    public static string RefreshNow => T("Refresh now", "Perbarui sekarang");
    public static string ShowInTray => T("Tray icon shows", "Ikon tray menampilkan");
    public static string LanguageMenu => T("Language", "Bahasa");
    public static string LanguageAuto => T("Automatic", "Otomatis");
    public static string LaunchAtLogin => T("Launch at login", "Buka saat login");
    public static string Quit => T("Quit", "Keluar");
    public static string Settings => T("Settings", "Pengaturan");
    public static string OpenPanel => T("Open", "Buka");
    public static string ChooseAgy => T("Locate agy.exe…", "Pilih lokasi agy.exe…");

    // Display choices
    public static string ChoiceGemini5h => T("Gemini · 5-hour", "Gemini · 5 jam");
    public static string ChoiceGeminiWeekly => T("Gemini · weekly", "Gemini · mingguan");
    public static string ChoiceThirdParty5h => T("Claude & GPT · 5-hour", "Claude & GPT · 5 jam");
    public static string ChoiceThirdPartyWeekly => T("Claude & GPT · weekly", "Claude & GPT · mingguan");
    public static string ChoiceHighest => T("Highest (all)", "Tertinggi (semua)");

    // Status / errors
    public static string UpdateFailed(string why) => T($"Update failed: {why}", $"Gagal memperbarui: {why}");
    public static string NotSignedIn => T("agy is not signed in. Run `agy` in a terminal and sign in first.", "agy belum login. Jalankan `agy` di terminal dan masuk dulu.");
    public static string NoAgy => T("Can't find the agy command. Install agy, set AGY_PATH, or pick agy.exe from the tray menu.", "Perintah agy tidak ditemukan. Pasang agy, set AGY_PATH, atau pilih agy.exe dari menu tray.");
    public static string Unreadable => T("Unrecognized agy output", "Keluaran agy tidak dikenali");
    public static string EmptyOutput => T("agy returned nothing", "Keluaran agy kosong");
    public static string Timeout(int seconds) => T($"agy did not respond (timeout {seconds}s)", $"agy tidak merespons (timeout {seconds} dtk)");
    public static string CannotRun(string why) => T($"Could not run agy: {why}", $"Gagal menjalankan agy: {why}");

    public static string Tooltip(string pool, string window, int percent, string? reset)
    {
        var baseText = T($"{pool} · {window}: {percent}% used", $"{pool} · {window}: {percent}% terpakai");
        return reset is null ? baseText : baseText + T($", resets in {reset}", $", reset {reset} lagi");
    }

    public static string FiveHourName => T("5-hour", "5 jam");
    public static string WeeklyName => T("weekly", "mingguan");
}
