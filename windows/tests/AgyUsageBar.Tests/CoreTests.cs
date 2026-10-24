using AgyUsageBar.Core;

namespace AgyUsageBar.Tests;

// One class on purpose: L.Current is global state, and xUnit runs the tests of a class one after another.
public class CoreTests : IDisposable
{
    private const string Fixture = """
    {"conversation_id":"","status":"SUCCESS","response":"x","num_turns":0,"command":{"name":"usage","data":{"description":"d","groups":[
    {"name":"Gemini Models","description":"Models within this group: Gemini Flash, Gemini Pro","buckets":[
    {"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.9882386326789856,"reset_time":"2026-10-30T23:07:13Z"},
    {"id":"gemini-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.9860554933547974,"reset_time":"2026-10-24T14:59:51Z"}]},
    {"name":"Claude and GPT models","description":"Models within this group: Claude Opus, Claude Sonnet, GPT-OSS","buckets":[
    {"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":1,"reset_time":"2026-10-31T10:08:04Z"},
    {"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":1,"reset_time":"2026-10-24T15:08:04Z"}]}]}}}
    """;

    private static readonly DateTimeOffset Now = UsageParser.ParseDate("2026-10-24T10:08:04Z")!.Value;

    public CoreTests()
    {
        Environment.SetEnvironmentVariable("AGY_USAGE_LANG", "en");
        L.Current = Lang.En;
    }

    public void Dispose() => L.Current = Lang.En;

    private static Snapshot Snap() => UsageParser.Parse(Fixture, Now);

    private static string Text(Snapshot s, DisplayChoice c, bool countdown = true) =>
        Fmt.BarText(Fmt.ChosenBucket(s, c)!, countdown, Now);

    // ---- parser and model ----

    [Fact]
    public void ParsesGroupsAndBuckets()
    {
        var s = Snap();
        Assert.Equal(2, s.Groups.Count);
        Assert.Equal(4, s.AllBuckets.Count);
        Assert.Equal("Gemini Flash, Gemini Pro", s.Groups[0].Models);
        Assert.Equal("gemini-5h", s.AllBuckets[0].Id);   // 5-hour first
        Assert.Equal(1, s.BucketById("gemini-5h")!.UsedPercent);
        Assert.True(s.BucketById("3p-5h")!.Untouched);
        Assert.False(s.BucketById("gemini-5h")!.Untouched);
        Assert.Equal("Gemini", s.Groups[0].ShortName);
        Assert.Equal("Claude & GPT", s.Groups[1].ShortName);
        Assert.False(s.Groups[0].Idle);
        Assert.True(s.Groups[1].Idle);
    }

    [Fact]
    public void ParsesFractionalSecondDates() => Assert.NotNull(UsageParser.ParseDate("2026-10-24T10:08:04.123Z"));

    [Fact]
    public void WindowStartAndElapsed()
    {
        var g5 = Snap().BucketById("gemini-5h")!;
        Assert.Equal(-493, (g5.WindowStart - Now).TotalSeconds, 2);   // 18000 s window - 17507 s left
        Assert.InRange(g5.Elapsed(Now), 0.02, 0.04);
    }

    [Fact]
    public void RoundsHalfAwayFromZero() =>
        Assert.Equal(3, new Bucket("x", "5h", 0.975, Now).UsedPercent);   // banker's rounding would give 2

    // ---- menu text ----

    [Fact]
    public void BarTextEnglish()
    {
        var s = Snap();
        Assert.Equal("1% · 4h 51m", Text(s, DisplayChoice.Gemini5h));
        Assert.Equal("1% wk · 6d 12h", Text(s, DisplayChoice.GeminiWeekly));
        Assert.Equal("0%", Text(s, DisplayChoice.ThirdParty5h));
        Assert.Equal("0% wk", Text(s, DisplayChoice.ThirdPartyWeekly));
        Assert.Equal("1% · 4h 51m", Text(s, DisplayChoice.Highest));
        Assert.Equal("1%", Text(s, DisplayChoice.Gemini5h, countdown: false));
    }

    [Fact]
    public void BarTextIndonesian()
    {
        L.Current = Lang.Id;
        var s = Snap();
        Assert.Equal("1% · 4j 51m", Text(s, DisplayChoice.Gemini5h));
        Assert.Equal("1% mgg · 6hr 12j", Text(s, DisplayChoice.GeminiWeekly));
        Assert.Equal("1hr", Fmt.Countdown(86400));
        Assert.Equal("1hr 1j", Fmt.Countdown(90000));
    }

    [Fact]
    public void LanguageDetection()
    {
        Assert.Equal(Lang.Id, L.Detect(new Dictionary<string, string?> { ["AGY_USAGE_LANG"] = "id" }, ["en-US"]));
        Assert.Equal(Lang.En, L.Detect(new Dictionary<string, string?> { ["AGY_USAGE_LANG"] = "en" }, ["id-ID"]));
        Assert.Equal(Lang.Id, L.Detect(new Dictionary<string, string?>(), ["id-ID", "en"]));
        Assert.Equal(Lang.En, L.Detect(new Dictionary<string, string?>(), ["en-US"]));
    }

    [Fact]
    public void CountdownFormats()
    {
        Assert.Equal("<1m", Fmt.Countdown(0));
        Assert.Equal("<1m", Fmt.Countdown(59));
        Assert.Equal("1m", Fmt.Countdown(60));
        Assert.Equal("1h", Fmt.Countdown(3600));
        Assert.Equal("1h 1m", Fmt.Countdown(3660));
        Assert.Equal("1d", Fmt.Countdown(86400));
        Assert.Equal("1d 1h", Fmt.Countdown(90000));
        Assert.Equal("<1m", Fmt.Countdown(-5));
    }

    [Fact]
    public void ColorBands()
    {
        Assert.Equal(Band.Ok, Bands.FromPercent(60));
        Assert.Equal(Band.Warn, Bands.FromPercent(61));
        Assert.Equal(Band.Warn, Bands.FromPercent(85));
        Assert.Equal(Band.Hot, Bands.FromPercent(86));
    }

    // ---- errors ----

    [Fact]
    public void RejectsGarbage() => Assert.Throws<FetchException>(() => UsageParser.Parse("hello", Now));

    [Fact]
    public void DetectsSignedOut()
    {
        var e = Assert.Throws<FetchException>(() => UsageParser.Parse("{\"status\":\"ERROR\",\"response\":\"Please sign in to continue\"}", Now));
        Assert.Equal(FetchKind.NotSignedIn, e.Kind);
    }

    [Fact]
    public void GenericErrorUsesFirstLine()
    {
        var e = Assert.Throws<FetchException>(() => UsageParser.Parse("{\"status\":\"ERROR\",\"response\":\"boom\\nmore\"}", Now));
        Assert.Equal(FetchKind.Failed, e.Kind);
        Assert.Equal("boom", e.Message);
    }

    [Fact]
    public void StderrIsCheckedWhenStdoutIsEmpty()
    {
        var e = Assert.Throws<FetchException>(() => AgyRunner.ParseOutput("", "Error: not logged in, please login"));
        Assert.Equal(FetchKind.NotSignedIn, e.Kind);
    }

    // ---- pacing, projection, trend ----

    private static Bucket Weekly(double used) => new("gemini-weekly", "weekly", 1 - used, Now.AddDays(6));
    private static Bucket Five(double used, TimeSpan resetIn, string window = "5h") => new("gemini-5h", window, 1 - used, Now + resetIn);

    private static History Hist(params (double Ago, double Used)[] pts)
    {
        var h = new History();
        foreach (var (ago, used) in pts)
        {
            var group = new UsageGroup("g", "", [Five(used, TimeSpan.FromHours(3))]);
            h.Append(new Snapshot(Now.AddSeconds(-ago), [group]));
        }
        return h;
    }

    [Fact]
    public void PacingAgainstEvenBurn()
    {
        Assert.Equal(Pacing.Under, Weekly(0.05).PacingAt(Now));
        Assert.Equal(Pacing.Even, Weekly(0.14).PacingAt(Now));
        Assert.Equal(Pacing.Over, Weekly(0.30).PacingAt(Now));
        Assert.Null(Weekly(0).PacingAt(Now));
    }

    [Fact]
    public void RisingUsageRunsOutBeforeReset()
    {
        var h = Hist((3600, 0.3), (1800, 0.4));
        var pace = Assert.IsType<Pace.Exhaust>(h.PaceFor(Five(0.5, TimeSpan.FromHours(3)), Now));
        Assert.Equal(9000, pace.In.TotalSeconds, 1);
        Assert.IsType<Pace.Safe>(h.PaceFor(Five(0.5, TimeSpan.FromHours(1)), Now));
    }

    [Fact]
    public void FlatOrShortHistoryGivesNoPace()
    {
        Assert.Null(Hist((3600, 0.5), (1800, 0.5)).PaceFor(Five(0.5, TimeSpan.FromHours(1)), Now));
        Assert.Null(Hist((300, 0.4)).PaceFor(Five(0.5, TimeSpan.FromHours(1)), Now));
    }

    [Fact]
    public void PaceIsCutAtTheLastReset()
    {
        var h = Hist((4800, 0.9), (4200, 0.95), (3600, 0.05), (1800, 0.1));
        var pace = Assert.IsType<Pace.Exhaust>(h.PaceFor(Five(0.2, TimeSpan.FromHours(6)), Now));
        Assert.Equal(19200, pace.In.TotalSeconds, 1);
    }

    [Fact]
    public void SmallDecayIsNotAReset()
    {
        var h = Hist((3600, 0.30), (1800, 0.299));
        var pace = Assert.IsType<Pace.Exhaust>(h.PaceFor(Five(0.5, TimeSpan.FromHours(3)), Now));
        Assert.Equal(9000, pace.In.TotalSeconds, 1);
    }

    [Fact]
    public void TrendHasPointsWindowAndForecast()
    {
        var h = Hist((3600, 0.3), (1800, 0.4));
        var b = Five(0.5, TimeSpan.FromHours(3));   // window started 2 h ago
        var trend = h.TrendFor(b, Now, h.Project(b, Now));
        Assert.NotNull(trend);
        Assert.Equal(3, trend!.Points.Count);
        Assert.Equal(0.5, trend.Points[^1].Used);
        Assert.Equal(-7200, (trend.Start - Now).TotalSeconds, 1);
        Assert.Equal(10800, (trend.End - Now).TotalSeconds, 1);
        Assert.Equal(9000, (trend.Forecast!.T - Now).TotalSeconds, 1);
        Assert.Equal(1.0, trend.Forecast.Used, 3);
    }

    [Fact]
    public void TrendIsAbsentWhenThereIsNothingHonestToDraw()
    {
        var h = Hist((3600, 0.3), (1800, 0.4));
        Assert.Null(Hist((10800, 0.1)).TrendFor(Five(0.5, TimeSpan.FromHours(3)), Now, null));   // sample before the window
        Assert.Null(h.TrendFor(Five(0.5, TimeSpan.FromHours(3), "weekly"), Now, null));          // weekly has no chart
        Assert.Null(h.TrendFor(Five(0, TimeSpan.FromHours(5)), Now, null));                      // not started
    }

    [Fact]
    public void HistoryDedupesHeartbeatsAndPrunes()
    {
        var s = Snap();
        var h = new History();
        Snapshot At(double secs) => s with { FetchedAt = Now.AddSeconds(secs) };
        h.Append(At(0)); h.Append(At(180));
        Assert.Equal(4, h.Samples.Count);          // unchanged adds nothing
        h.Append(At(16 * 60));
        Assert.Equal(8, h.Samples.Count);          // 15-minute heartbeat
        h.Append(At(8 * 86400));
        Assert.All(h.Samples, x => Assert.True(x.T >= Now.AddDays(1)));   // older than 7 days dropped
    }

    // ---- manager ----

    private static UsageManager Manager(Func<string?, CancellationToken, Task<Snapshot>> fetch, string? dir = null) =>
        new(new Store(dir ?? Path.Combine(Path.GetTempPath(), "agy-usage-test-" + Guid.NewGuid())), fetch, () => Now);

    [Fact]
    public async Task ManagerPublishesData()
    {
        using var m = Manager((_, _) => Task.FromResult(Snap()));
        await m.FetchAsync(CancellationToken.None);
        Assert.Equal(LoadKind.Ok, m.Load);
        Assert.Null(m.Banner);
        var bar = m.Bar;
        Assert.Equal("1", bar.IconText);
        Assert.Equal(Band.Ok, bar.Band);
        Assert.True(bar.IsData);
        Assert.Contains("Gemini", bar.Tooltip);
        Assert.Equal("Gemini", m.SelectedGroup(m.Snapshot!, null)!.ShortName);
        Assert.Equal("Claude & GPT", m.SelectedGroup(m.Snapshot!, "Claude and GPT models")!.ShortName);
    }

    [Fact]
    public async Task ManagerMapsErrorsAndBacksOff()
    {
        var kind = FetchKind.NoAgy;
        using var m = Manager((_, _) => throw new FetchException(kind, "x"));
        Assert.Equal(TimeSpan.FromMinutes(3), m.NextDelay());
        await m.FetchAsync(CancellationToken.None);
        Assert.Equal(LoadKind.NoAgy, m.Load);
        Assert.Equal("!", m.Bar.IconText);
        Assert.Equal(TimeSpan.FromSeconds(180), m.NextDelay());
        kind = FetchKind.NotSignedIn;
        await m.FetchAsync(CancellationToken.None);
        Assert.Equal(LoadKind.NotSignedIn, m.Load);
        Assert.Equal(TimeSpan.FromSeconds(360), m.NextDelay());
        kind = FetchKind.Failed;
        await m.FetchAsync(CancellationToken.None);
        await m.FetchAsync(CancellationToken.None);
        await m.FetchAsync(CancellationToken.None);
        Assert.Equal(LoadKind.Error, m.Load);
        Assert.Equal(TimeSpan.FromSeconds(900), m.NextDelay());   // capped at 15 minutes
    }

    [Fact]
    public async Task ManagerKeepsLastGoodDataOnTransientError()
    {
        var fail = false;
        using var m = Manager((_, _) => fail ? throw new FetchException(FetchKind.Failed, "timeout") : Task.FromResult(Snap()));
        await m.FetchAsync(CancellationToken.None);
        fail = true;
        await m.FetchAsync(CancellationToken.None);
        Assert.Equal(LoadKind.Error, m.Load);
        Assert.NotNull(m.Snapshot);
        Assert.True(m.Bar.IsData);
        Assert.EndsWith(" !", m.Bar.Tooltip);
        Assert.Contains("timeout", m.Banner);
    }

    [Fact]
    public async Task ManagerPersistsSettingsAndData()
    {
        var dir = Path.Combine(Path.GetTempPath(), "agy-usage-test-" + Guid.NewGuid());
        using (var m = Manager((_, _) => Task.FromResult(Snap()), dir))
        {
            await m.FetchAsync(CancellationToken.None);
            m.Choice = DisplayChoice.GeminiWeekly;
            m.Language = "id";
            Assert.Equal(Lang.Id, L.Current);
        }
        using var again = Manager((_, _) => throw new FetchException(FetchKind.Failed, "x"), dir);
        Assert.Equal(DisplayChoice.GeminiWeekly, again.Choice);
        Assert.Equal("id", again.Language);
        Assert.NotNull(again.Snapshot);   // last good data is shown at launch
    }
}
