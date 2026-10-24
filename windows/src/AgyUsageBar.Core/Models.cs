using System.Text.Json.Serialization;

namespace AgyUsageBar.Core;

public enum Band { Ok, Warn, Hot }

public enum Pacing { Under, Even, Over }

public static class Bands
{
    /// Green 0-60, amber 61-85, red 86-100 (percent used).
    public static Band FromPercent(int percent) => percent <= 60 ? Band.Ok : percent <= 85 ? Band.Warn : Band.Hot;
}

/// One quota window (for example "gemini-5h"). <c>Remaining</c> is 0..1, exactly agy's remaining_fraction.
public sealed record Bucket(string Id, string Window, double Remaining, DateTimeOffset ResetTime)
{
    [JsonIgnore] public bool IsFiveHour => Window == "5h";
    [JsonIgnore] public double Used => Math.Clamp(1 - Remaining, 0, 1);
    [JsonIgnore] public int UsedPercent => (int)Math.Round(Used * 100, MidpointRounding.AwayFromZero);

    /// The window has not started: agy then reports reset_time = now + window, so a countdown would be fake.
    [JsonIgnore] public bool Untouched => Remaining >= 0.9999;

    [JsonIgnore] public string WindowLabel => IsFiveHour ? L.FiveHourName : L.WeeklyName;
    [JsonIgnore] public TimeSpan WindowLength => IsFiveHour ? TimeSpan.FromHours(5) : TimeSpan.FromDays(7);

    /// Window start = reset - length (only meaningful once the window has started).
    [JsonIgnore] public DateTimeOffset WindowStart => ResetTime - WindowLength;
    [JsonIgnore] public Band Band => Bands.FromPercent(UsedPercent);

    public double Elapsed(DateTimeOffset now) => Math.Clamp((now - WindowStart) / WindowLength, 0, 1);

    /// Compares consumption with a perfectly even burn over the window.
    public Pacing? PacingAt(DateTimeOffset now)
    {
        if (Untouched) return null;
        var e = Elapsed(now);
        if (Used < e * 0.85) return Pacing.Under;
        if (Used > e * 1.15 + 0.01) return Pacing.Over;
        return Pacing.Even;
    }
}

public sealed record UsageGroup(string Name, string Models, IReadOnlyList<Bucket> Buckets)
{
    [JsonIgnore] public string Id => Name;
    [JsonIgnore] public Bucket? Five => Buckets.FirstOrDefault(b => b.IsFiveHour);
    [JsonIgnore] public Bucket? Weekly => Buckets.FirstOrDefault(b => !b.IsFiveHour);
    [JsonIgnore] public double WorstUsed => Buckets.Count == 0 ? 0 : Buckets.Max(b => b.Used);
    [JsonIgnore] public bool Idle => Buckets.All(b => b.Untouched);

    /// "Gemini" / "Claude & GPT" for the two known pools, otherwise the name agy reports.
    [JsonIgnore]
    public string ShortName
    {
        get
        {
            var key = Buckets.Count > 0 ? Buckets[0].Id : "";
            if (key.StartsWith("gemini", StringComparison.Ordinal)) return "Gemini";
            if (key.StartsWith("3p", StringComparison.Ordinal)) return "Claude & GPT";
            return Name;
        }
    }
}

public sealed record Snapshot(DateTimeOffset FetchedAt, IReadOnlyList<UsageGroup> Groups)
{
    /// 5-hour first, then weekly, per group. Ties for "highest" resolve to the first one.
    [JsonIgnore]
    public IReadOnlyList<Bucket> AllBuckets =>
        Groups.SelectMany(g => g.Buckets.OrderBy(b => b.IsFiveHour ? 0 : 1)).ToList();

    public Bucket? BucketById(string id) => AllBuckets.FirstOrDefault(b => b.Id == id);
}

public enum DisplayChoice { Gemini5h, GeminiWeekly, ThirdParty5h, ThirdPartyWeekly, Highest }

public static class DisplayChoices
{
    public static readonly DisplayChoice[] All =
        [DisplayChoice.Gemini5h, DisplayChoice.GeminiWeekly, DisplayChoice.ThirdParty5h, DisplayChoice.ThirdPartyWeekly, DisplayChoice.Highest];

    public static string? BucketId(this DisplayChoice c) => c switch
    {
        DisplayChoice.Gemini5h => "gemini-5h",
        DisplayChoice.GeminiWeekly => "gemini-weekly",
        DisplayChoice.ThirdParty5h => "3p-5h",
        DisplayChoice.ThirdPartyWeekly => "3p-weekly",
        _ => null,
    };

    public static string Label(this DisplayChoice c) => c switch
    {
        DisplayChoice.Gemini5h => L.ChoiceGemini5h,
        DisplayChoice.GeminiWeekly => L.ChoiceGeminiWeekly,
        DisplayChoice.ThirdParty5h => L.ChoiceThirdParty5h,
        DisplayChoice.ThirdPartyWeekly => L.ChoiceThirdPartyWeekly,
        _ => L.ChoiceHighest,
    };
}

public enum FetchKind { NoAgy, NotSignedIn, Failed }

public sealed class FetchException(FetchKind kind, string message) : Exception(message)
{
    public FetchKind Kind { get; } = kind;
}
