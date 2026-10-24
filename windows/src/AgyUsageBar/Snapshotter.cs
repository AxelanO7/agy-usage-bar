using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using AgyUsageBar.Core;

namespace AgyUsageBar;

/// Command-line render modes used for screenshots and for checking the UI on CI without a display:
///   AgyUsageBar --snapshot out.png [--dark] [--lang en|id] [--pool gemini|3p]     (demo data)
///   AgyUsageBar --icons out.png                                                  (tray icon states)
public static class Snapshotter
{
    private static string? Option(string[] args, string name)
    {
        var i = Array.IndexOf(args, name);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    public static (Snapshot, History) Demo()
    {
        var now = UsageParser.ParseDate("2026-10-24T12:00:00Z")!.Value;
        Bucket B(string id, string w, double used, TimeSpan reset) => new(id, w, 1 - used, now + reset);
        var g5 = B("gemini-5h", "5h", 0.72, TimeSpan.FromMinutes(130));
        var gw = B("gemini-weekly", "weekly", 0.41, TimeSpan.FromHours(53));
        var t5 = B("3p-5h", "5h", 0.30, TimeSpan.FromHours(3));
        var tw = B("3p-weekly", "weekly", 0.05, TimeSpan.FromDays(6));
        var snap = new Snapshot(now,
        [
            new UsageGroup("Gemini Models", "Gemini Flash, Gemini Pro", [gw, g5]),
            new UsageGroup("Claude and GPT models", "Claude Opus, Claude Sonnet, GPT-OSS", [tw, t5]),
        ]);
        var h = new History();
        void Add(double minutesAgo, Bucket b, double used) =>
            h.Append(new Snapshot(now.AddMinutes(-minutesAgo), [new UsageGroup("g", "", [b with { Remaining = 1 - used }])]));
        foreach (var (ago, used) in new[] { (165.0, 0.02), (130.0, 0.10), (90.0, 0.27), (60.0, 0.42), (30.0, 0.58) }) Add(ago, g5, used);
        Add(12 * 60, gw, 0.36);
        Add(60, t5, 0.10);
        return (snap, h);
    }

    public static int RunPopup(string[] args)
    {
        var path = Option(args, "--snapshot")!;
        if (Option(args, "--lang") is { } lang) L.Current = lang.StartsWith("id", StringComparison.OrdinalIgnoreCase) ? Lang.Id : Lang.En;
        var dark = args.Contains("--dark");

        var (snap, history) = Demo();
        var dir = Path.Combine(Path.GetTempPath(), "agy-usage-demo-" + Guid.NewGuid());
        new Store(dir).Write(history, "history.json");
        Environment.SetEnvironmentVariable("AGY_USAGE_LANG", Option(args, "--lang") ?? "en");
        using var manager = new UsageManager(new Store(dir), (_, _) => throw new InvalidOperationException("offline"), () => snap.FetchedAt);
        manager.Preview(snap);
        string? pool = null;
        if (Option(args, "--pool") is { } p)
        {
            var key = p.Equals("3p", StringComparison.OrdinalIgnoreCase) ? "claude" : p.ToLowerInvariant();
            pool = snap.Groups.FirstOrDefault(g => g.ShortName.Contains(key, StringComparison.OrdinalIgnoreCase))?.Id;
        }

        var panel = PopupView.Build(new PopupContext(manager, new Theme(dark), pool, _ => { }, () => { }, _ => { }));
        return Save(panel, path);
    }

    private static int Save(FrameworkElement element, string path)
    {
        const double scale = 2;
        element.Measure(new System.Windows.Size(double.PositiveInfinity, double.PositiveInfinity));
        element.Arrange(new Rect(element.DesiredSize));
        element.UpdateLayout();
        var w = (int)Math.Ceiling(element.DesiredSize.Width * scale);
        var h = (int)Math.Ceiling(element.DesiredSize.Height * scale);
        var rtb = new RenderTargetBitmap(w, h, 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        rtb.Render(element);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(rtb));
        using var fs = File.Create(path);
        encoder.Save(fs);
        Console.WriteLine($"PNG {w}x{h} -> {path}");
        return 0;
    }

    /// A sheet of tray icons (enlarged 6x with hard pixels) on a dark and a light taskbar.
    public static int RunIcons(string[] args)
    {
        var path = Option(args, "--icons")!;
        L.Current = Lang.En;
        BarState S(double used, bool idle = false) => new(((int)Math.Round(used * 100)).ToString(), idle ? 0 : used, Bands.FromPercent((int)Math.Round(used * 100)), "", true);
        var states = new[]
        {
            S(0, idle: true), S(0.02), S(0.41), S(0.72), S(0.93), S(1.0),
            new BarState("!", null, Band.Warn, "", false), new BarState("…", null, Band.Ok, "", false),
        };
        const int size = 32, zoom = 6, pad = 12;
        var cell = size * zoom + pad * 2;
        using var sheet = new Bitmap(cell * states.Length, cell * 2);
        using var g = Graphics.FromImage(sheet);
        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
        for (var row = 0; row < 2; row++)
        {
            using var bg = new SolidBrush(row == 0 ? System.Drawing.Color.FromArgb(32, 32, 32) : System.Drawing.Color.FromArgb(243, 243, 243));
            g.FillRectangle(bg, 0, row * cell, sheet.Width, cell);
            for (var i = 0; i < states.Length; i++)
            {
                using var icon = TrayIconRenderer.Render(states[i], size);
                g.DrawImage(icon, new Rectangle(i * cell + pad, row * cell + pad, size * zoom, size * zoom));
            }
        }
        sheet.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        Console.WriteLine($"PNG -> {path}");
        return 0;
    }
}
