using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace AgyUsageBar;

/// Small helpers to build the popup in code.
public static class Ui
{
    public static readonly FontFamily Body = new("Segoe UI Variable Text, Segoe UI");
    public static readonly FontFamily Display = new("Segoe UI Variable Display, Segoe UI");
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    public static SolidColorBrush Brush(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    public static TextBlock Text(string text, double size, Color color, FontWeight? weight = null, FontFamily? family = null) => new()
    {
        Text = text,
        FontSize = size,
        Foreground = Brush(color),
        FontWeight = weight ?? FontWeights.Normal,
        FontFamily = family ?? Body,
        TextWrapping = TextWrapping.Wrap,
    };

    /// Adds top spacing so a StackPanel behaves like a vertical stack with a gap.
    public static T Gap<T>(T element, double top = 12) where T : FrameworkElement
    {
        element.Margin = new Thickness(0, top, 0, 0);
        return element;
    }

    public static Border Card(UIElement child, Theme t, double padding = 16) => new()
    {
        Padding = new Thickness(padding),
        CornerRadius = new CornerRadius(14),
        Background = Brush(t.Card),
        BorderBrush = Brush(t.CardBorder),
        BorderThickness = new Thickness(1),
        Child = child,
    };

    public static Ellipse Dot(Color c, double size = 7) => new() { Width = size, Height = size, Fill = Brush(c), VerticalAlignment = VerticalAlignment.Center };
}
