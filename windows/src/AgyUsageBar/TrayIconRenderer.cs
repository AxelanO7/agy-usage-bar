using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using AgyUsageBar.Core;

namespace AgyUsageBar;

/// Draws the notification-area icon: a dark rounded tile, the used percent as digits in the status color,
/// and a thin fill bar along the bottom. Windows trays cannot show text next to an icon (unlike the macOS
/// menu bar), so the number lives inside the icon.
public static class TrayIconRenderer
{
    private static readonly Color Tile = Color.FromArgb(240, 30, 30, 33);

    public static Bitmap Render(BarState bar, int size)
    {
        var bmp = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.Clear(Color.Transparent);

        var accent = bar.IsData ? AccentOf(bar.Band) : Color.FromArgb(255, 255, 159, 10);
        var radius = size * 0.24f;
        using (var path = RoundedRect(new RectangleF(0, 0, size, size), radius))
        using (var fill = new SolidBrush(Tile))
            g.FillPath(fill, path);

        var barH = Math.Max(2f, size * 0.12f);
        var inset = size * 0.14f;
        var barRect = new RectangleF(inset, size - inset - barH, size - inset * 2, barH);
        if (bar.IsData)
        {
            using var track = new SolidBrush(Color.FromArgb(70, 255, 255, 255));
            using var trackPath = RoundedRect(barRect, barH / 2);
            g.FillPath(track, trackPath);
            var f = (float)Math.Clamp(bar.Fraction ?? 0, 0, 1);
            if (f > 0)
            {
                var fillRect = new RectangleF(barRect.X, barRect.Y, Math.Max(barH, barRect.Width * f), barRect.Height);
                using var fillBrush = new SolidBrush(accent);
                using var fillPath = RoundedRect(fillRect, barH / 2);
                g.FillPath(fillBrush, fillPath);
            }
        }

        var text = bar.IconText;
        var fontPx = text.Length switch { <= 1 => size * 0.66f, 2 => size * 0.58f, _ => size * 0.44f };
        using var font = new Font("Segoe UI Semibold", fontPx, FontStyle.Regular, GraphicsUnit.Pixel);
        using var brush = new SolidBrush(bar.IsData && bar.Fraction is 0 ? Color.FromArgb(255, 200, 200, 205) : accent);
        var area = new RectangleF(0, size * 0.02f, size, size - inset - barH - size * 0.02f);
        using var fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap };
        g.DrawString(text, font, brush, area, fmt);
        return bmp;
    }

    public static Icon ToIcon(Bitmap bmp)
    {
        var h = bmp.GetHicon();
        try { return (Icon)Icon.FromHandle(h).Clone(); }
        finally { DestroyIcon(h); }
    }

    public static Color AccentOf(Band band) => band switch
    {
        Band.Ok => Color.FromArgb(255, 50, 215, 75),
        Band.Warn => Color.FromArgb(255, 255, 159, 10),
        _ => Color.FromArgb(255, 255, 69, 58),
    };

    private static GraphicsPath RoundedRect(RectangleF r, float radius)
    {
        var d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);
}
