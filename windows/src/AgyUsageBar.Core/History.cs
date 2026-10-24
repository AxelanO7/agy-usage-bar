using System.Text.Json.Serialization;

namespace AgyUsageBar.Core;

public sealed record Sample(DateTimeOffset T, string Id, double Used);

public abstract record Pace
{
    /// At the current rate the limit runs out before the reset.
    public sealed record Exhaust(TimeSpan In) : Pace;

    public sealed record Safe : Pace;
}

/// Burn rate (fraction of the limit per second) and what it means for this window.
public sealed record Projection(double Rate, Pace Pace);

public sealed record TrendPoint(DateTimeOffset T, double Used);

/// Usage during the current window for the chart, plus the dashed forecast segment.
public sealed record Trend(IReadOnlyList<TrendPoint> Points, DateTimeOffset Start, DateTimeOffset End, TrendPoint? Forecast);

/// Per-window usage history (max 7 days), used to estimate the burn rate and draw the trend chart.
public sealed class History
{
    public static readonly TimeSpan Keep = TimeSpan.FromDays(7);
    public static readonly TimeSpan Heartbeat = TimeSpan.FromMinutes(15);

    /// agy can lower the used percentage slightly inside one window (old usage decays); only a drop this big counts as a reset.
    public const double ResetDrop = 0.02;

    public List<Sample> Samples { get; set; } = [];

    public void Append(Snapshot snap)
    {
        foreach (var b in snap.AllBuckets)
        {
            var last = Samples.LastOrDefault(s => s.Id == b.Id);
            if (last is not null && Math.Abs(last.Used - b.Used) < 1e-6 && snap.FetchedAt - last.T < Heartbeat) continue;
            Samples.Add(new Sample(snap.FetchedAt, b.Id, b.Used));
        }
        var cutoff = snap.FetchedAt - Keep;
        Samples.RemoveAll(s => s.T < cutoff);
    }

    /// Samples of one bucket since <c>from</c>, ending with the current reading, cut at the last sharp drop (a reset).
    private List<Sample> Recent(Bucket b, DateTimeOffset from, DateTimeOffset now)
    {
        var pts = Samples.Where(s => s.Id == b.Id && s.T >= from && s.T <= now).OrderBy(s => s.T).ToList();
        pts.Add(new Sample(now, b.Id, b.Used));
        for (var i = pts.Count - 2; i >= 0; i--)
        {
            if (pts[i].Used - pts[i + 1].Used > ResetDrop)
            {
                pts = pts.GetRange(i + 1, pts.Count - i - 1);
                break;
            }
        }
        return pts;
    }

    /// Rate = rise in used fraction divided by time since the last reset inside the look-back.
    /// 5-hour: look back 90 min (min span 8 min); weekly: 24 h (min span 1 h).
    public Projection? Project(Bucket b, DateTimeOffset now)
    {
        var lookback = b.IsFiveHour ? TimeSpan.FromMinutes(90) : TimeSpan.FromHours(24);
        var minSpan = b.IsFiveHour ? TimeSpan.FromMinutes(8) : TimeSpan.FromHours(1);
        var pts = Recent(b, now - lookback, now);
        var first = pts[0];
        var span = now - first.T;
        if (span < minSpan) return null;
        var delta = b.Used - first.Used;
        if (delta <= 0.0005) return null;
        var rate = delta / span.TotalSeconds;
        var eta = TimeSpan.FromSeconds((1 - b.Used) / rate);
        return new Projection(rate, now + eta < b.ResetTime ? new Pace.Exhaust(eta) : new Pace.Safe());
    }

    public Pace? PaceFor(Bucket b, DateTimeOffset now) => Project(b, now)?.Pace;

    /// Chart data for a started 5-hour window. Needs a few minutes of real samples; nothing is invented before the first one.
    public Trend? TrendFor(Bucket b, DateTimeOffset now, Projection? projection)
    {
        if (!b.IsFiveHour || b.Untouched) return null;
        var pts = Recent(b, b.WindowStart, now);
        if (pts.Count < 2 || now - pts[0].T < TimeSpan.FromMinutes(5)) return null;
        TrendPoint? forecast = null;
        if (projection is not null)
        {
            var horizon = Math.Min((b.ResetTime - now).TotalSeconds, (1 - b.Used) / projection.Rate);
            if (horizon > 60)
                forecast = new TrendPoint(now + TimeSpan.FromSeconds(horizon), Math.Min(1, b.Used + projection.Rate * horizon));
        }
        return new Trend(pts.Select(p => new TrendPoint(p.T, p.Used)).ToList(), b.WindowStart, b.ResetTime, forecast);
    }
}
