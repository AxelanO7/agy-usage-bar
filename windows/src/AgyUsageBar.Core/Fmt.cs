namespace AgyUsageBar.Core;

/// What the tray icon shows: a short text, a fill fraction, a color band and a tooltip.
public sealed record BarState(string IconText, double? Fraction, Band Band, string Tooltip, bool IsData);

public static class Fmt
{
    /// 6d 12h · 4h 52m · 7m · &lt;1m   (Indonesian: 6hr 12j · 4j 52m)
    public static string Countdown(double seconds)
    {
        var s = (int)Math.Max(0, seconds);
        int d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60;
        string du = L.DayUnit, hu = L.HourUnit, mu = L.MinuteUnit;
        if (d > 0) return h > 0 ? $"{d}{du} {h}{hu}" : $"{d}{du}";
        if (h > 0) return m > 0 ? $"{h}{hu} {m}{mu}" : $"{h}{hu}";
        if (m > 0) return $"{m}{mu}";
        return "<1m";
    }

    public static string Countdown(TimeSpan span) => Countdown(span.TotalSeconds);

    public static string Clock(DateTimeOffset t) => t.ToLocalTime().ToString("HH:mm", L.Culture);

    /// "Sat 07:07" / "Sab 07:07"
    public static string WeekdayClock(DateTimeOffset t) => t.ToLocalTime().ToString("ddd HH:mm", L.Culture);

    public static Bucket? ChosenBucket(Snapshot snap, DisplayChoice choice)
    {
        var id = choice.BucketId();
        if (id is not null && snap.BucketById(id) is { } b) return b;
        // Highest used; ties keep the first one (5-hour), like the macOS app.
        Bucket? best = null;
        foreach (var x in snap.AllBuckets) if (best is null || best.Used < x.Used) best = x;
        return best;
    }

    /// "72% · 2h 10m"   weekly: "41% wk · 2d 5h"   not started: "0%"
    public static string BarText(Bucket b, bool showCountdown, DateTimeOffset now)
    {
        var t = $"{b.UsedPercent}%";
        if (!b.IsFiveHour) t += $" {L.WeekTag}";
        if (showCountdown && !b.Untouched) t += $" · {Countdown(b.ResetTime - now)}";
        return t;
    }

    public static string Tooltip(Snapshot snap, Bucket b, DateTimeOffset now)
    {
        var pool = snap.Groups.FirstOrDefault(g => g.Buckets.Contains(b))?.ShortName ?? "";
        return L.Tooltip(pool, b.WindowLabel, b.UsedPercent, b.Untouched ? null : Countdown(b.ResetTime - now));
    }
}
