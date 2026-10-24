namespace AgyUsageBar.Core;

public enum LoadKind { Idle, Loading, Ok, Error, NotSignedIn, NoAgy }

/// Polls agy, keeps the last good data, history and settings. UI-agnostic: it raises <see cref="Changed"/>
/// from background threads and the UI marshals to its own thread.
public sealed class UsageManager : IDisposable
{
    public event Action? Changed;

    private readonly object gate = new();
    private readonly Store store;
    private readonly Func<string?, CancellationToken, Task<Snapshot>> fetcher;
    private readonly Func<DateTimeOffset> clock;
    private readonly History history;
    private readonly Settings settings;
    private Snapshot? snapshot;
    private LoadKind load = LoadKind.Idle;
    private string? message;
    private bool refreshing;
    private int failures;
    private DateTimeOffset? lastAttempt;
    private DateTimeOffset now;
    private CancellationTokenSource? cts;
    private Timer? tick;

    public UsageManager(Store? store = null, Func<string?, CancellationToken, Task<Snapshot>>? fetcher = null, Func<DateTimeOffset>? clock = null)
    {
        this.store = store ?? new Store(Store.DefaultDir);
        this.fetcher = fetcher ?? ((path, ct) => AgyRunner.FetchAsync(path, ct));
        this.clock = clock ?? (() => DateTimeOffset.UtcNow);
        now = this.clock();
        history = this.store.Read<History>("history.json") ?? new History();
        snapshot = this.store.Read<Snapshot>("last-usage.json");
        settings = this.store.Read<Settings>("settings.json") ?? new Settings();
        ApplyLanguage();
    }

    // ---- state (read from any thread) ----

    public Snapshot? Snapshot { get { lock (gate) return snapshot; } }
    public LoadKind Load { get { lock (gate) return load; } }
    public bool Refreshing { get { lock (gate) return refreshing; } }
    public DateTimeOffset Now { get { lock (gate) return now; } }
    public string? AgyPath { get { lock (gate) return settings.AgyPath; } }

    public DisplayChoice Choice
    {
        get { lock (gate) return settings.Choice; }
        set { lock (gate) { settings.Choice = value; store.Write(settings, "settings.json"); } Changed?.Invoke(); }
    }

    /// "auto" | "en" | "id"
    public string Language
    {
        get { lock (gate) return settings.Lang; }
        set { lock (gate) { settings.Lang = value; store.Write(settings, "settings.json"); ApplyLanguage(); } Changed?.Invoke(); }
    }

    public void SetAgyPath(string? path)
    {
        lock (gate) { settings.AgyPath = path; store.Write(settings, "settings.json"); failures = 0; }
        Refresh();
    }

    private void ApplyLanguage() =>
        L.Current = settings.Lang switch { "en" => Lang.En, "id" => Lang.Id, _ => L.Detect() };

    public string? Banner
    {
        get
        {
            lock (gate)
                return load switch
                {
                    LoadKind.Error => L.UpdateFailed(message ?? ""),
                    LoadKind.NotSignedIn => L.NotSignedIn,
                    LoadKind.NoAgy => L.NoAgy,
                    _ => null,
                };
        }
    }

    public BarState Bar
    {
        get
        {
            lock (gate)
            {
                switch (load)
                {
                    case LoadKind.NoAgy: return new BarState("!", null, Band.Warn, L.NoAgy, false);
                    case LoadKind.NotSignedIn: return new BarState("!", null, Band.Warn, L.NotSignedIn, false);
                }
                var isError = load == LoadKind.Error;
                if (snapshot is { } s && Fmt.ChosenBucket(s, settings.Choice) is { } b)
                {
                    var tip = Fmt.Tooltip(s, b, now) + (isError ? " !" : "");
                    return new BarState(b.UsedPercent.ToString(), b.Used, b.Band, tip, true);
                }
                return new BarState(isError ? "!" : "…", null, Band.Ok, isError ? L.UpdateFailed(message ?? "") : L.Loading, false);
            }
        }
    }

    // ---- derived data for the UI ----

    public Projection? Project(Bucket b) { lock (gate) return history.Project(b, now); }
    public Trend? TrendFor(Bucket b) { lock (gate) return history.TrendFor(b, now, history.Project(b, now)); }

    /// The pool shown in the popup: the user's pick, otherwise the pool of the bucket shown in the tray icon.
    public UsageGroup? SelectedGroup(Snapshot snap, string? poolId)
    {
        if (poolId is not null && snap.Groups.FirstOrDefault(g => g.Id == poolId) is { } picked) return picked;
        if (Fmt.ChosenBucket(snap, Choice) is { } b && snap.Groups.FirstOrDefault(g => g.Buckets.Contains(b)) is { } g) return g;
        return snap.Groups.FirstOrDefault();
    }

    public bool IsPinned(Bucket b) => Snapshot is { } s && Fmt.ChosenBucket(s, Choice)?.Id == b.Id;

    // ---- polling ----

    public void Start()
    {
        cts = new CancellationTokenSource();
        var ct = cts.Token;
        tick = new Timer(_ => { lock (gate) now = clock(); Changed?.Invoke(); }, null, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(30));
        _ = Task.Run(async () =>
        {
            while (!ct.IsCancellationRequested)
            {
                await FetchAsync(ct);
                try { await Task.Delay(NextDelay(), ct); } catch (OperationCanceledException) { break; }
            }
        }, ct);
    }

    /// 3 minutes; doubled after each consecutive failure, up to 15 minutes.
    public TimeSpan NextDelay()
    {
        lock (gate) return failures == 0 ? TimeSpan.FromMinutes(3) : TimeSpan.FromSeconds(Math.Min(180 * Math.Pow(2, failures - 1), 900));
    }

    public void Refresh() => _ = Task.Run(() => FetchAsync(CancellationToken.None));

    public void RefreshIfStale(TimeSpan? after = null)
    {
        lock (gate) if (lastAttempt is { } t && clock() - t < (after ?? TimeSpan.FromSeconds(30))) return;
        Refresh();
    }

    /// After the PC wakes from sleep: give the network a moment, then fetch.
    public async void OnResume()
    {
        await Task.Delay(TimeSpan.FromSeconds(5));
        await FetchAsync(CancellationToken.None);
    }

    public async Task FetchAsync(CancellationToken ct)
    {
        string? path;
        lock (gate)
        {
            if (refreshing) return;
            refreshing = true;
            lastAttempt = clock();
            if (snapshot is null) load = LoadKind.Loading;
            path = settings.AgyPath;
        }
        Changed?.Invoke();
        try
        {
            var snap = await fetcher(path, ct);
            lock (gate)
            {
                snapshot = snap;
                load = LoadKind.Ok;
                message = null;
                failures = 0;
                now = clock();
                history.Append(snap);
                store.Write(snap, "last-usage.json");
                store.Write(history, "history.json");
            }
        }
        catch (FetchException e)
        {
            lock (gate)
            {
                failures++;
                now = clock();
                message = e.Message;
                load = e.Kind switch { FetchKind.NoAgy => LoadKind.NoAgy, FetchKind.NotSignedIn => LoadKind.NotSignedIn, _ => LoadKind.Error };
            }
        }
        catch (OperationCanceledException)
        {
            // shutting down
        }
        catch (Exception e)
        {
            lock (gate) { failures++; now = clock(); message = e.Message; load = LoadKind.Error; }
        }
        finally
        {
            lock (gate) refreshing = false;
        }
        Changed?.Invoke();
    }

    /// For the `--snapshot` render mode: use data that was already fetched, persist nothing.
    public void Preview(Snapshot snap)
    {
        lock (gate) { snapshot = snap; load = LoadKind.Ok; now = snap.FetchedAt; }
    }

    public void Dispose()
    {
        cts?.Cancel();
        tick?.Dispose();
    }
}
