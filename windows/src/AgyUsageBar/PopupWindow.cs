using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace AgyUsageBar;

/// Borderless flyout that opens next to the tray icon and closes when it loses focus.
public sealed class PopupWindow : Window
{
    private readonly Grid host = new() { Margin = new Thickness(16) };   // room for the drop shadow
    private System.Drawing.Point lastCursor;
    public DateTime LastHiddenUtc { get; private set; } = DateTime.MinValue;

    /// True while the settings menu is open: the popup must not close when the menu takes focus.
    public bool KeepOpen { get; set; }

    public PopupWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.WidthAndHeight;
        UseLayoutRounding = true;
        Content = host;
        Deactivated += (_, _) => { if (!KeepOpen) HideSoft(); };
        KeyDown += (_, e) => { if (e.Key == Key.Escape) HideSoft(); };
    }

    public void SetContent(FrameworkElement panel)
    {
        panel.Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 3, Direction = 270, Opacity = 0.35, Color = Colors.Black };
        host.Children.Clear();
        host.Children.Add(panel);
    }

    public void HideSoft()
    {
        if (!IsVisible) return;
        Hide();
        LastHiddenUtc = DateTime.UtcNow;
    }

    /// Opens above (or below) the tray icon, inside the working area of the monitor under the cursor.
    public void ShowNear(System.Drawing.Point cursor)
    {
        lastCursor = cursor;
        var wa = System.Windows.Forms.Screen.FromPoint(cursor).WorkingArea;
        Opacity = 0;
        Left = wa.Left;           // park inside the target monitor first so WPF picks its DPI
        Top = wa.Top;
        Show();
        Dispatcher.Invoke(() => { }, DispatcherPriority.Render);
        UpdateLayout();
        Place();
        Opacity = 1;
        Activate();
        SetForegroundWindow(new WindowInteropHelper(this).Handle);
    }

    /// The content height can change while the popup is open (chart appears, pool switch): keep it inside the screen.
    public void Refit()
    {
        if (!IsVisible) return;
        UpdateLayout();
        Place();
    }

    private void Place()
    {
        var wa = System.Windows.Forms.Screen.FromPoint(lastCursor).WorkingArea;
        var dpi = VisualTreeHelper.GetDpi(this);
        var w = (int)Math.Ceiling(ActualWidth * dpi.DpiScaleX);
        var h = (int)Math.Ceiling(ActualHeight * dpi.DpiScaleY);
        var shadow = (int)Math.Round(16 * dpi.DpiScaleX);   // transparent margin around the panel
        var gap = (int)Math.Round(4 * dpi.DpiScaleX);

        var x = lastCursor.X - w / 2;
        x = Math.Clamp(x, wa.Left - shadow + gap, Math.Max(wa.Left - shadow + gap, wa.Right - w + shadow - gap));
        var middle = (wa.Top + wa.Bottom) / 2;
        var y = lastCursor.Y > middle ? wa.Bottom - h + shadow - gap : wa.Top - shadow + gap;

        var hwnd = new WindowInteropHelper(this).Handle;
        SetWindowPos(hwnd, new IntPtr(-1), x, y, 0, 0, 0x0001 | 0x0010);   // HWND_TOPMOST, SWP_NOSIZE | SWP_NOACTIVATE
    }

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);
}
