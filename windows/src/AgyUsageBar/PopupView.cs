using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using AgyUsageBar.Core;

namespace AgyUsageBar;

public sealed record PopupContext(
    UsageManager Manager,
    Theme Theme,
    string? PoolId,
    Action<string> SelectPool,
    Action Refresh,
    Action<FrameworkElement> OpenSettings);

/// The popup content, built in code so the layout stays easy to diff against the macOS SwiftUI view.
public static class PopupView
{
    public static Border Build(PopupContext c)
    {
        var m = c.Manager;
        var t = c.Theme;
        var snap = m.Snapshot;
        var root = new StackPanel { Width = 306 };

        root.Children.Add(Header(c, snap));
        if (m.Banner is { } banner) root.Children.Add(Ui.Gap(Banner(banner, t)));

        if (snap is not null && m.SelectedGroup(snap, c.PoolId) is { } group)
        {
            if (snap.Groups.Count > 1) root.Children.Add(Ui.Gap(PoolPicker(snap, group, c)));
            if (group.Five is { } five) root.Children.Add(Ui.Gap(Hero(five, m, t)));
            if (group.Weekly is { } weekly) root.Children.Add(Ui.Gap(Weekly(weekly, m, t)));
        }
        else if (m.Banner is null)
        {
            var wait = Ui.Text(L.Loading, 12, t.Secondary);
            wait.HorizontalAlignment = HorizontalAlignment.Center;
            wait.Margin = new Thickness(0, 36, 0, 36);
            root.Children.Add(wait);
        }

        root.Children.Add(Ui.Gap(Ui.Text(L.Source, 10, t.Tertiary)));

        return new Border
        {
            Width = 340,
            Padding = new Thickness(16),
            CornerRadius = new CornerRadius(14),
            Background = Ui.Brush(t.Bg),
            BorderBrush = Ui.Brush(t.CardBorder),
            BorderThickness = new Thickness(1),
            Child = root,
        };
    }

    // ---- header ----

    private static Grid Header(PopupContext c, Snapshot? snap)
    {
        var t = c.Theme;
        var m = c.Manager;
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var left = new StackPanel();
        left.Children.Add(Ui.Text("Antigravity", 16, t.Text, FontWeights.SemiBold, Ui.Display));
        var status = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 2, 0, 0) };
        var statusColor = m.Load switch { LoadKind.Ok => t.Ok, LoadKind.Idle or LoadKind.Loading => t.Warn, _ => t.Hot };
        var dot = Ui.Dot(statusColor, 6);
        dot.Margin = new Thickness(0, 0, 5, 0);
        status.Children.Add(dot);
        status.Children.Add(Ui.Text(snap is null ? L.Loading : L.Updated(Fmt.Clock(snap.FetchedAt)), 11, t.Secondary));
        left.Children.Add(status);
        grid.Children.Add(left);

        var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        right.Children.Add(IconButton("\uE72C", L.RefreshNow, t, () => c.Refresh()));      // Refresh
        var gear = IconButton("\uE713", L.Settings, t, null);                              // Settings
        gear.MouseLeftButtonUp += (_, _) => c.OpenSettings(gear);
        right.Children.Add(gear);
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        return grid;
    }

    private static Border IconButton(string glyph, string tip, Theme t, Action? onClick)
    {
        var icon = Ui.Text(glyph, 13, t.Text, family: Ui.Icons);
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        icon.VerticalAlignment = VerticalAlignment.Center;
        var b = new Border
        {
            Width = 30, Height = 30, CornerRadius = new CornerRadius(15),
            Background = Brushes.Transparent, Child = icon, ToolTip = tip, Cursor = Cursors.Hand,
        };
        b.MouseEnter += (_, _) => b.Background = Ui.Brush(t.Hover);
        b.MouseLeave += (_, _) => b.Background = Brushes.Transparent;
        if (onClick is not null) b.MouseLeftButtonUp += (_, _) => onClick();
        return b;
    }

    private static Border Banner(string text, Theme t)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        var icon = Ui.Text("\uE7BA", 12, t.Hot, family: Ui.Icons);   // Warning
        icon.Margin = new Thickness(0, 1, 8, 0);
        row.Children.Add(icon);
        var msg = Ui.Text(text, 11, t.Text);
        msg.MaxWidth = 260;
        row.Children.Add(msg);
        return new Border
        {
            Padding = new Thickness(10), CornerRadius = new CornerRadius(10),
            Background = Ui.Brush(Theme.Mix(t.Bg, t.Hot, 0.16)), Child = row,
        };
    }

    // ---- pool switch ----

    private static Border PoolPicker(Snapshot snap, UsageGroup selected, PopupContext c)
    {
        var t = c.Theme;
        var grid = new UniformGrid { Columns = snap.Groups.Count };
        foreach (var g in snap.Groups)
        {
            var on = g.Id == selected.Id;
            var dotColor = g.Idle ? t.Tertiary : t.Accent(Bands.FromPercent((int)Math.Round(g.WorstUsed * 100, MidpointRounding.AwayFromZero)));
            var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            var dot = Ui.Dot(dotColor);
            dot.Margin = new Thickness(0, 0, 6, 0);
            row.Children.Add(dot);
            row.Children.Add(Ui.Text(g.ShortName, 12, on ? t.Text : t.Secondary, FontWeights.SemiBold));
            var btn = new Border
            {
                Padding = new Thickness(0, 7, 0, 7), CornerRadius = new CornerRadius(8), Cursor = Cursors.Hand, Child = row,
                Background = on ? Ui.Brush(t.Selected) : Brushes.Transparent,
                BorderBrush = on && !t.Dark ? Ui.Brush(t.CardBorder) : Brushes.Transparent,
                BorderThickness = new Thickness(1),
            };
            var id = g.Id;
            btn.MouseLeftButtonUp += (_, _) => c.SelectPool(id);
            grid.Children.Add(btn);
        }
        return new Border
        {
            Padding = new Thickness(3), CornerRadius = new CornerRadius(10),
            Background = Ui.Brush(t.Dark ? Theme.Mix(t.Bg, t.Text, 0.07) : Theme.Mix(t.Bg, t.Text, 0.05)), Child = grid,
        };
    }

    // ---- 5-hour hero card ----

    private static Border Hero(Bucket b, UsageManager m, Theme t)
    {
        var accent = t.Accent(b.Band);
        var projection = m.Project(b);
        var outer = new StackPanel();

        var top = new Grid();
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.ColumnDefinitions.Add(new ColumnDefinition());

        var ringHost = new Grid { Width = 112, Height = 112 };
        ringHost.Children.Add(new RingGauge { Used = b.Used, Accent = accent, Tail = Theme.Mix(t.Card, accent, 0.55), Track = t.Track, Width = 112, Height = 112 });
        var center = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        var pct = Ui.Text($"{b.UsedPercent}%", 30, accent, FontWeights.Bold, Ui.Display);
        pct.HorizontalAlignment = HorizontalAlignment.Center;
        var used = Ui.Text(L.Used, 9, t.Secondary, FontWeights.SemiBold);
        used.HorizontalAlignment = HorizontalAlignment.Center;
        center.Children.Add(pct);
        center.Children.Add(used);
        ringHost.Children.Add(center);
        top.Children.Add(ringHost);

        var info = new StackPanel { Margin = new Thickness(16, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        info.Children.Add(CaptionRow(L.FiveHourCaption, m.IsPinned(b), t));
        if (b.Untouched)
        {
            info.Children.Add(Ui.Gap(Ui.Text(L.NotUsedYet, 20, t.Text, FontWeights.SemiBold, Ui.Display), 3));
            info.Children.Add(Ui.Gap(Ui.Text(L.WindowStartsHint, 12, t.Secondary), 3));
        }
        else
        {
            info.Children.Add(Ui.Gap(Ui.Text(Fmt.Countdown(b.ResetTime - m.Now), 30, t.Text, FontWeights.SemiBold, Ui.Display), 1));
            info.Children.Add(Ui.Text(L.UntilReset, 12, t.Secondary));
            if (PaceLine(projection?.Pace, t) is { } pace) info.Children.Add(Ui.Gap(pace, 6));
        }
        Grid.SetColumn(info, 1);
        top.Children.Add(info);
        outer.Children.Add(top);

        if (m.TrendFor(b) is { } trend) outer.Children.Add(Ui.Gap(TrendBlock(trend, projection, accent, t), 14));
        return Ui.Card(outer, t);
    }

    private static FrameworkElement? PaceLine(Pace? pace, Theme t)
    {
        switch (pace)
        {
            case Pace.Exhaust ex:
                return IconText(Flame(t.Warn), L.RunsOut(Fmt.Countdown(ex.In)), t.Warn);
            case Pace.Safe:
                var check = Ui.Text("\uE930", 13, t.Secondary, family: Ui.Icons);   // Completed (check in circle)
                return IconText(check, L.LastsUntilReset, t.Secondary);
            default:
                return null;
        }
    }

    private static StackPanel IconText(UIElement icon, string text, Color color)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        if (icon is FrameworkElement fe) fe.Margin = new Thickness(0, 0, 6, 0);
        row.Children.Add(icon);
        row.Children.Add(Ui.Text(text, 12, color, FontWeights.Medium));
        return row;
    }

    private static Path Flame(Color color) => new()
    {
        Width = 11, Height = 14, Stretch = Stretch.Uniform, Fill = Ui.Brush(color), VerticalAlignment = VerticalAlignment.Center,
        Data = Geometry.Parse("M8,0 C8.6,3.2 12,5.2 12,9.4 C12,12.9 9.5,15 7,15 C4.4,15 2,12.9 2,9.8 C2,7.6 3.2,6.2 4.4,5 C4.6,6.6 5.4,7.6 6.4,8 C6.2,5.2 6.6,2.2 8,0 Z"),
    };

    private static StackPanel CaptionRow(string text, bool pinned, Theme t)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(Ui.Text(text, 10, t.Secondary, FontWeights.SemiBold));
        if (pinned)
        {
            var pin = Ui.Text("\uE718", 10, t.Tertiary, family: Ui.Icons);   // Pin
            pin.Margin = new Thickness(6, 0, 0, 0);
            pin.ToolTip = L.PinnedHelp;
            row.Children.Add(pin);
        }
        return row;
    }

    private static StackPanel TrendBlock(Trend trend, Projection? projection, Color accent, Theme t)
    {
        var color = projection?.Pace is Pace.Exhaust ? t.Warn : accent;
        var chartRow = new Grid { Height = 60 };
        chartRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(32) });
        chartRow.ColumnDefinitions.Add(new ColumnDefinition());
        var labels = new Grid();
        labels.RowDefinitions.Add(new RowDefinition());
        labels.RowDefinitions.Add(new RowDefinition());
        var hi = Ui.Text("100%", 9, t.Tertiary);
        hi.HorizontalAlignment = HorizontalAlignment.Left;
        var lo = Ui.Text("0", 9, t.Tertiary);
        lo.HorizontalAlignment = HorizontalAlignment.Left;
        lo.VerticalAlignment = VerticalAlignment.Bottom;
        Grid.SetRow(lo, 1);
        labels.Children.Add(hi);
        labels.Children.Add(lo);
        chartRow.Children.Add(labels);
        var chart = new TrendChart { Data = trend, Accent = color, Grid = Theme.Mix(t.Card, t.Text, 0.14) };
        Grid.SetColumn(chart, 1);
        chartRow.Children.Add(chart);

        var axis = new Grid { Margin = new Thickness(32, 4, 0, 0) };
        axis.ColumnDefinitions.Add(new ColumnDefinition());
        axis.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        axis.ColumnDefinitions.Add(new ColumnDefinition());
        var start = Ui.Text(L.Started(Fmt.Clock(trend.Start)), 10, t.Tertiary);
        var end = Ui.Text(L.ResetsShort(Fmt.Clock(trend.End)), 10, t.Tertiary);
        end.HorizontalAlignment = HorizontalAlignment.Right;
        axis.Children.Add(start);
        Grid.SetColumn(end, 2);
        axis.Children.Add(end);
        if (trend.Forecast is not null)
        {
            var key = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            key.Children.Add(new Line { X1 = 0, X2 = 16, Y1 = 1, Y2 = 1, Stroke = Ui.Brush(color), StrokeThickness = 1.8, StrokeDashArray = [2.2, 2.2], Width = 16, Height = 2, Margin = new Thickness(0, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center });
            key.Children.Add(Ui.Text(L.Forecast, 10, color));
            Grid.SetColumn(key, 1);
            axis.Children.Add(key);
        }

        var block = new StackPanel();
        block.Children.Add(chartRow);
        block.Children.Add(axis);
        return block;
    }

    // ---- weekly card ----

    private static Border Weekly(Bucket b, UsageManager m, Theme t)
    {
        var accent = t.Accent(b.Band);
        var head = new Grid();
        head.ColumnDefinitions.Add(new ColumnDefinition());
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var cap = CaptionRow(L.WeeklyCaption, m.IsPinned(b), t);
        cap.VerticalAlignment = VerticalAlignment.Center;
        head.Children.Add(cap);
        var value = Ui.Text(b.Untouched ? L.NotUsedShort : $"{b.UsedPercent}%", 22, b.Untouched ? t.Secondary : accent, FontWeights.Bold, Ui.Display);
        Grid.SetColumn(value, 1);
        head.Children.Add(value);

        var bar = new BarGauge
        {
            Used = b.Used, Accent = accent, Tail = Theme.Mix(t.Card, accent, 0.7), Track = t.Track,
            TickColor = Color.FromArgb(180, t.Text.R, t.Text.G, t.Text.B),
            Tick = b.Untouched ? null : b.Elapsed(m.Now), Height = 14,
        };

        var foot = new Grid();
        foot.ColumnDefinitions.Add(new ColumnDefinition());
        foot.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = Ui.Text(b.Untouched ? L.WindowStartsHint : L.Resets(Fmt.WeekdayClock(b.ResetTime)), 11, t.Secondary);
        foot.Children.Add(left);
        if (b.PacingAt(m.Now) is { } p)
        {
            var (label, color) = p switch
            {
                Pacing.Under => (L.UnderPace, t.Ok),
                Pacing.Over => (L.OverPace, t.Warn),
                _ => (L.OnPace, t.Secondary),
            };
            var pace = Ui.Text(label, 11, color);
            Grid.SetColumn(pace, 1);
            foot.Children.Add(pace);
        }

        var stack = new StackPanel();
        stack.Children.Add(head);
        stack.Children.Add(Ui.Gap(bar, 10));
        stack.Children.Add(Ui.Gap(foot, 8));
        return Ui.Card(stack, t);
    }
}
