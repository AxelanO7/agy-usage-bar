using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using AgyUsageBar.Core;

namespace AgyUsageBar;

/// Circular gauge: faint track plus an arc from 12 o'clock that gets stronger toward its head
/// (drawn as short flat segments with a blended color, round caps on the two ends).
public sealed class RingGauge : FrameworkElement
{
    public double Used { get; init; }
    public Color Accent { get; init; }
    public Color Tail { get; init; }
    public Color Track { get; init; }
    public double Thickness { get; init; } = 11;

    protected override void OnRender(DrawingContext dc)
    {
        var size = Math.Min(ActualWidth, ActualHeight);
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        var r = (size - Thickness) / 2;
        dc.DrawEllipse(null, new Pen(Ui.Brush(Track), Thickness), center, r, r);

        var used = Math.Clamp(Used, 0, 1);
        if (used <= 0) return;
        var sweep = 360 * Math.Max(used, 0.004);
        var n = Math.Max(1, (int)Math.Ceiling(sweep / 5));
        for (var i = 0; i < n; i++)
        {
            var a0 = -90 + sweep * i / n;
            var a1 = -90 + sweep * (i + 1) / n + (i < n - 1 ? 0.7 : 0);   // tiny overlap hides anti-aliasing seams
            var color = Theme.Mix(Tail, Accent, (i + 0.5) / n);
            var pen = new Pen(Ui.Brush(color), Thickness)
            {
                StartLineCap = i == 0 ? PenLineCap.Round : PenLineCap.Flat,
                EndLineCap = i == n - 1 ? PenLineCap.Round : PenLineCap.Flat,
            };
            var geo = new StreamGeometry();
            using (var ctx = geo.Open())
            {
                ctx.BeginFigure(PointAt(center, r, a0), false, false);
                ctx.ArcTo(PointAt(center, r, a1), new Size(r, r), 0, a1 - a0 > 180, SweepDirection.Clockwise, true, false);
            }
            geo.Freeze();
            dc.DrawGeometry(null, pen, geo);
        }
    }

    private static Point PointAt(Point c, double r, double deg)
    {
        var rad = deg * Math.PI / 180;
        return new Point(c.X + r * Math.Cos(rad), c.Y + r * Math.Sin(rad));
    }
}

/// Horizontal gauge with an optional "even pace" tick.
public sealed class BarGauge : FrameworkElement
{
    public double Used { get; init; }
    public Color Accent { get; init; }
    public Color Tail { get; init; }
    public Color Track { get; init; }
    public Color TickColor { get; init; }
    public double? Tick { get; init; }

    protected override void OnRender(DrawingContext dc)
    {
        var w = ActualWidth;
        var cy = ActualHeight / 2;
        dc.DrawRoundedRectangle(Ui.Brush(Track), null, new Rect(0, cy - 4, w, 8), 4, 4);
        var used = Math.Clamp(Used, 0, 1);
        if (used > 0)
        {
            var fill = new LinearGradientBrush(Tail, Accent, 0);
            fill.Freeze();
            dc.DrawRoundedRectangle(fill, null, new Rect(0, cy - 4, Math.Max(8, w * used), 8), 4, 4);
        }
        if (Tick is { } t)
        {
            var x = Math.Clamp(w * t - 1, 0, w - 2);
            dc.DrawRoundedRectangle(Ui.Brush(TickColor), null, new Rect(x, cy - 7, 2, 14), 1, 1);
        }
    }
}

/// Usage during the current 5-hour window with the dashed forecast segment.
public sealed class TrendChart : FrameworkElement
{
    public Trend Data { get; init; } = null!;
    public Color Accent { get; init; }
    public Color Grid { get; init; }

    protected override void OnRender(DrawingContext dc)
    {
        const double pad = 4;
        double w = ActualWidth, h = ActualHeight - pad * 2;
        var span = Math.Max((Data.End - Data.Start).TotalSeconds, 1);
        double X(DateTimeOffset t) => (t - Data.Start).TotalSeconds / span * w;
        double Y(double u) => pad + h * (1 - Math.Clamp(u, 0, 1));

        var gridPen = new Pen(Ui.Brush(Grid), 1) { DashStyle = new DashStyle(new double[] { 2, 3 }, 0) };
        foreach (var g in new[] { 0.0, 0.5, 1.0 }) dc.DrawLine(gridPen, new Point(0, Y(g)), new Point(w, Y(g)));
        if (Data.Points.Count == 0) return;

        var first = Data.Points[0];
        var last = Data.Points[^1];

        var area = new StreamGeometry();
        using (var ctx = area.Open())
        {
            ctx.BeginFigure(new Point(X(first.T), Y(0)), true, true);
            foreach (var p in Data.Points) ctx.LineTo(new Point(X(p.T), Y(p.Used)), false, false);
            ctx.LineTo(new Point(X(last.T), Y(0)), false, false);
        }
        area.Freeze();
        var fill = new LinearGradientBrush(
            [new GradientStop(Color.FromArgb(77, Accent.R, Accent.G, Accent.B), 0), new GradientStop(Color.FromArgb(5, Accent.R, Accent.G, Accent.B), 1)],
            new Point(0, 0), new Point(0, 1));
        fill.Freeze();
        dc.DrawGeometry(fill, null, area);

        var line = new StreamGeometry();
        using (var ctx = line.Open())
        {
            ctx.BeginFigure(new Point(X(first.T), Y(first.Used)), false, false);
            foreach (var p in Data.Points.Skip(1)) ctx.LineTo(new Point(X(p.T), Y(p.Used)), true, true);
        }
        line.Freeze();
        dc.DrawGeometry(null, new Pen(Ui.Brush(Accent), 2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round }, line);

        if (Data.Forecast is { } f)
        {
            var dash = new Pen(Ui.Brush(Accent), 1.8) { DashStyle = new DashStyle(new double[] { 2.2, 2.2 }, 0), StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
            dc.DrawLine(dash, new Point(X(last.T), Y(last.Used)), new Point(X(f.T), Y(f.Used)));
        }
        dc.DrawEllipse(Ui.Brush(Accent), null, new Point(X(last.T), Y(last.Used)), 4, 4);
    }
}
