using System;
using Microsoft.Win32;
using System.Windows.Media;

namespace AgyUsageBar;

/// Colors for the popup. Follows the Windows "app mode" (light/dark) unless forced (snapshot mode).
public sealed class Theme
{
    public bool Dark { get; }
    public Color Bg { get; }
    public Color Card { get; }
    public Color CardBorder { get; }
    public Color Text { get; }
    public Color Secondary { get; }
    public Color Tertiary { get; }
    public Color Track { get; }
    public Color Hover { get; }
    public Color Selected { get; }
    public Color Ok { get; }
    public Color Warn { get; }
    public Color Hot { get; }

    public Theme(bool dark)
    {
        Dark = dark;
        if (dark)
        {
            Bg = Rgb(0x2B2B2B); Card = Rgb(0x353535); CardBorder = Rgb(0x454545);
            Text = Rgb(0xFFFFFF); Secondary = Rgb(0xC4C4C4); Tertiary = Rgb(0x8C8C8C);
            Track = Rgb(0x4A4A4A); Hover = Rgb(0x404040); Selected = Rgb(0x4A4A4A);
            Ok = Rgb(0x32D74B); Warn = Rgb(0xFF9F0A); Hot = Rgb(0xFF453A);
        }
        else
        {
            Bg = Rgb(0xF3F3F3); Card = Rgb(0xFFFFFF); CardBorder = Rgb(0xE2E2E2);
            Text = Rgb(0x1B1B1B); Secondary = Rgb(0x5E5E5E); Tertiary = Rgb(0x8A8A8A);
            Track = Rgb(0xE3E3E3); Hover = Rgb(0xE9E9E9); Selected = Rgb(0xFFFFFF);
            Ok = Rgb(0x1E9E3A); Warn = Rgb(0xD97706); Hot = Rgb(0xD93025);
        }
    }

    public static Theme FromSystem() => new(IsSystemDark());

    public Color Accent(AgyUsageBar.Core.Band band) => band switch
    {
        AgyUsageBar.Core.Band.Ok => Ok,
        AgyUsageBar.Core.Band.Warn => Warn,
        _ => Hot,
    };

    public static Color Rgb(int rgb) => Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

    public static Color Mix(Color a, Color b, double t) => Color.FromRgb(
        (byte)Math.Round(a.R + (b.R - a.R) * t),
        (byte)Math.Round(a.G + (b.G - a.G) * t),
        (byte)Math.Round(a.B + (b.B - a.B) * t));

    private static bool IsSystemDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
        }
        catch
        {
            return false;
        }
    }
}
