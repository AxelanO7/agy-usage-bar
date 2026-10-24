# Installing Agy Usage Bar

Written for people **and for AI coding agents** (OpenCode, Claude Code, Codex, Cursor, Gemini/agy, ...). If you are an agent, follow this file literally.

## Rules for agents

- Do the steps below and nothing else. Say what you are about to run before you run it.
- Do **not** read, print or copy credentials, tokens, keychain items or `~/.gemini` contents. The app never needs them.
- Do **not** install `agy` for the user, use `sudo`/admin rights, change git remotes, or push anything.
- Stop and tell the user if a prerequisite is missing instead of improvising.

## 1. Prerequisites

The Antigravity CLI must be installed and signed in:

```sh
agy --version                                  # Windows: agy.exe --version
agy -p "/usage" --output-format json           # should print JSON containing "status":"SUCCESS"
```

- Command not found: stop. Tell the user to install `agy` from https://antigravity.google/ and sign in.
- Output says not signed in: stop. Ask the user to run `agy` once in a terminal and sign in.

(The second command makes no model call and uses no quota; it is exactly what the app runs.)

## 2. Install (pick the user's OS)

### macOS 13 or newer

```sh
curl -fsSL -o /tmp/agy-usage-install.sh https://raw.githubusercontent.com/AxelanO7/agy-usage-bar/main/scripts/install.sh
cat /tmp/agy-usage-install.sh        # read it: it downloads the latest release zip and copies the app to ~/Applications
bash /tmp/agy-usage-install.sh
```

### Windows 10 or 11 (PowerShell)

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/AxelanO7/agy-usage-bar/main/scripts/install.ps1 -OutFile $env:TEMP\agy-usage-install.ps1
Get-Content $env:TEMP\agy-usage-install.ps1      # read it: it downloads the latest release exe to %LOCALAPPDATA%\Programs\AgyUsageBar
powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\agy-usage-install.ps1 -LaunchAtLogin
```

`-LaunchAtLogin` is optional: ask the user first (it adds a per-user Run entry). Leave it out if they did not say yes.

## 3. Verify

- macOS: `pgrep -x AgyUsageBar` prints a process id, and a ring with a percentage appears in the menu bar.
- Windows: `Get-Process AgyUsageBar` lists the process, and a small tile with a number appears in the system tray (Windows 11 may hide it in the `^` overflow: the user can drag it onto the taskbar).
- Data check: `~/Library/Application Support/AgyUsageBar/last-usage.json` (macOS) or `%LOCALAPPDATA%\AgyUsageBar\last-usage.json` (Windows) exists after a few seconds.

Then tell the user what you installed, where, and that clicking the icon opens the panel. Launch at login: macOS gear icon in the panel -> *Launch at login*; Windows tray right-click -> *Launch at login*.

## If there is no release yet (build from source)

macOS (needs the Xcode Command Line Tools):

```sh
git clone https://github.com/AxelanO7/agy-usage-bar.git && cd agy-usage-bar/macos
./make_app.sh && mkdir -p ~/Applications && cp -R AgyUsageBar.app ~/Applications/ && open ~/Applications/AgyUsageBar.app
```

Windows (needs the .NET 10 SDK):

```powershell
git clone https://github.com/AxelanO7/agy-usage-bar.git; cd agy-usage-bar
dotnet publish windows/src/AgyUsageBar -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish
Start-Process .\publish\AgyUsageBar.exe
```

## Update

Run the install step again: it replaces the old copy.

## Uninstall

- macOS: quit the app from the gear menu, delete `~/Applications/AgyUsageBar.app` and `~/Library/Application Support/AgyUsageBar`.
- Windows: tray right-click -> *Quit*, delete `%LOCALAPPDATA%\Programs\AgyUsageBar` and `%LOCALAPPDATA%\AgyUsageBar`, remove the Start Menu shortcut, and turn off *Launch at login* first if it was on.
