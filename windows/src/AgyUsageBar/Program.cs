using System;
using System.Linq;
using System.Threading;
using System.Windows;
using AgyUsageBar.Core;

namespace AgyUsageBar;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Contains("--snapshot")) return Snapshotter.RunPopup(args);
        if (args.Contains("--icons")) return Snapshotter.RunIcons(args);

        // One tray icon per user session.
        using var mutex = new Mutex(true, @"Local\AgyUsageBar.SingleInstance", out var first);
        if (!first) return 0;

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using var manager = new UsageManager();
        using var tray = new TrayController(manager);
        manager.Start();
        return app.Run();
    }
}
