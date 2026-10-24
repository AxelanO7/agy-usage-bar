using System;
using System.Drawing;
using System.Windows.Forms;
using System.Windows.Threading;
using AgyUsageBar.Core;
using Microsoft.Win32;

namespace AgyUsageBar;

/// The notification-area icon, its right-click menu and the popup that a left click opens.
public sealed class TrayController : IDisposable
{
    private readonly UsageManager manager;
    private readonly Dispatcher ui;
    private readonly NotifyIcon notify;
    private readonly ContextMenuStrip menu = new();
    private PopupWindow? popup;
    private string? poolId;

    public TrayController(UsageManager manager)
    {
        this.manager = manager;
        ui = Dispatcher.CurrentDispatcher;
        notify = new NotifyIcon { ContextMenuStrip = menu };
        notify.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) TogglePopup(); };
        menu.Opening += (_, _) => BuildMenu();
        manager.Changed += () => ui.BeginInvoke(Update);
        menu.Closed += (_, _) =>
        {
            if (popup is null) return;
            popup.KeepOpen = false;
            if (popup.IsVisible) popup.Activate();
        };
        SystemEvents.PowerModeChanged += OnPower;
        Update();
        notify.Visible = true;   // only once it has an icon
    }

    private void OnPower(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume) manager.OnResume();
    }

    private void Update()
    {
        var bar = manager.Bar;
        var size = Math.Max(16, SystemInformation.SmallIconSize.Width);
        using var bmp = TrayIconRenderer.Render(bar, size);
        var icon = TrayIconRenderer.ToIcon(bmp);
        var old = notify.Icon;
        notify.Icon = icon;
        old?.Dispose();
        notify.Text = bar.Tooltip.Length <= 127 ? bar.Tooltip : bar.Tooltip[..126] + "…";
        if (popup is { IsVisible: true }) Rebuild();
    }

    // ---- popup ----

    private void TogglePopup()
    {
        if (popup is { IsVisible: true })
        {
            popup.HideSoft();
            return;
        }
        // The click that closed the popup by deactivating it also reaches the icon: do not reopen at once.
        if (popup is not null && (DateTime.UtcNow - popup.LastHiddenUtc).TotalMilliseconds < 300) return;

        manager.RefreshIfStale();
        popup ??= new PopupWindow();
        Rebuild();
        popup.ShowNear(Cursor.Position);
    }

    private void Rebuild()
    {
        if (popup is null) return;
        popup.SetContent(PopupView.Build(new PopupContext(
            manager, Theme.FromSystem(), poolId,
            id => { poolId = id; Rebuild(); },
            manager.Refresh,
            _ => ShowSettingsMenu())));
        popup.Dispatcher.BeginInvoke(popup.Refit, DispatcherPriority.Loaded);
    }

    private void ShowSettingsMenu()
    {
        if (popup is not null) popup.KeepOpen = true;
        BuildMenu();
        menu.Show(Cursor.Position);
    }

    // ---- right-click menu ----

    private void BuildMenu()
    {
        menu.Items.Clear();

        var open = new ToolStripMenuItem(L.OpenPanel) { Font = new Font(menu.Font, FontStyle.Bold) };
        open.Click += (_, _) => TogglePopup();
        menu.Items.Add(open);

        var refresh = new ToolStripMenuItem(L.RefreshNow);
        refresh.Click += (_, _) => manager.Refresh();
        menu.Items.Add(refresh);
        menu.Items.Add(new ToolStripSeparator());

        var show = new ToolStripMenuItem(L.ShowInTray);
        foreach (var choice in DisplayChoices.All)
        {
            var c = choice;
            var item = new ToolStripMenuItem(c.Label()) { Checked = manager.Choice == c };
            item.Click += (_, _) => manager.Choice = c;
            show.DropDownItems.Add(item);
        }
        menu.Items.Add(show);

        var lang = new ToolStripMenuItem(L.LanguageMenu);
        foreach (var (key, label) in new[] { ("auto", L.LanguageAuto), ("en", "English"), ("id", "Bahasa Indonesia") })
        {
            var k = key;
            var item = new ToolStripMenuItem(label) { Checked = manager.Language == k };
            item.Click += (_, _) => manager.Language = k;
            lang.DropDownItems.Add(item);
        }
        menu.Items.Add(lang);

        var login = new ToolStripMenuItem(L.LaunchAtLogin) { Checked = Autostart.IsEnabled };
        login.Click += (_, _) => Autostart.Set(!Autostart.IsEnabled);
        menu.Items.Add(login);

        var locate = new ToolStripMenuItem(L.ChooseAgy);
        locate.Click += (_, _) => LocateAgy();
        menu.Items.Add(locate);

        menu.Items.Add(new ToolStripSeparator());
        var quit = new ToolStripMenuItem(L.Quit);
        quit.Click += (_, _) => System.Windows.Application.Current.Shutdown();
        menu.Items.Add(quit);
    }

    private void LocateAgy()
    {
        using var dialog = new System.Windows.Forms.OpenFileDialog
        {
            Title = L.ChooseAgy,
            Filter = "agy (agy.exe;agy.cmd)|agy.exe;agy.cmd|All files (*.*)|*.*",
            CheckFileExists = true,
        };
        if (dialog.ShowDialog() == DialogResult.OK) manager.SetAgyPath(dialog.FileName);
    }

    public void Dispose()
    {
        SystemEvents.PowerModeChanged -= OnPower;
        notify.Visible = false;
        notify.Icon?.Dispose();
        notify.Dispose();
        menu.Dispose();
        popup?.Close();
    }
}
