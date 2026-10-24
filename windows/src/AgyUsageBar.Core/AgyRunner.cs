using System.Diagnostics;
using System.Text;

namespace AgyUsageBar.Core;

/// Reads quota through the official CLI: <c>agy -p "/usage" --output-format json</c>.
/// It never touches tokens or the credential store and makes no model call (0 tokens), so it uses no quota.
public static class AgyRunner
{
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(45);

    /// Order: explicit path (settings) -> AGY_PATH -> PATH -> well-known install folders.
    public static string? Locate(string? configured = null)
    {
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured)) return configured;
        var env = Environment.GetEnvironmentVariable("AGY_PATH");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(env)) return env;

        string[] names = OperatingSystem.IsWindows() ? ["agy.exe", "agy.cmd", "agy.bat"] : ["agy"];
        var separators = new[] { Path.PathSeparator };
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(separators, StringSplitOptions.RemoveEmptyEntries))
            foreach (var n in names)
                try { var p = Path.Combine(dir.Trim('"'), n); if (File.Exists(p)) return p; } catch { /* bad PATH entry */ }

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string[] known = OperatingSystem.IsWindows()
            ?
            [
                Path.Combine(local, "Antigravity", "agy.exe"),
                Path.Combine(local, "Antigravity", "bin", "agy.exe"),
                Path.Combine(local, "Programs", "Antigravity", "agy.exe"),
                Path.Combine(local, "Programs", "agy", "agy.exe"),
                Path.Combine(home, ".local", "bin", "agy.exe"),
                Path.Combine(roaming, "npm", "agy.cmd"),
            ]
            :
            [
                Path.Combine(home, ".local", "bin", "agy"),
                "/opt/homebrew/bin/agy",
                "/usr/local/bin/agy",
            ];
        return known.FirstOrDefault(File.Exists);
    }

    public static async Task<Snapshot> FetchAsync(string? configuredPath = null, CancellationToken ct = default)
    {
        var path = Locate(configuredPath) ?? throw new FetchException(FetchKind.NoAgy, L.NoAgy);

        var psi = new ProcessStartInfo
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        };
        psi.Environment["NO_COLOR"] = "1";
        var args = new[] { "-p", "/usage", "--output-format", "json" };
        if (OperatingSystem.IsWindows() && (path.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) || path.EndsWith(".bat", StringComparison.OrdinalIgnoreCase)))
        {
            // Batch shims (for example npm's) must run through cmd.exe. `/s` plus an outer pair of quotes keeps paths with spaces intact.
            psi.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe";
            psi.Arguments = $"/d /s /c \"\"{path}\" {string.Join(' ', args)}\"";
        }
        else
        {
            psi.FileName = path;
            foreach (var a in args) psi.ArgumentList.Add(a);
        }

        using var proc = new Process { StartInfo = psi };
        try { proc.Start(); }
        catch (Exception e) { throw new FetchException(FetchKind.Failed, L.CannotRun(e.Message)); }

        var stdout = new StringBuilder();
        var stderr = new StringBuilder();
        proc.OutputDataReceived += (_, e) => { if (e.Data is not null) lock (stdout) stdout.AppendLine(e.Data); };
        proc.ErrorDataReceived += (_, e) => { if (e.Data is not null) lock (stderr) stderr.AppendLine(e.Data); };
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();
        try { proc.StandardInput.Close(); } catch { /* already closed */ }

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(Timeout);
        try { await proc.WaitForExitAsync(cts.Token); }
        catch (OperationCanceledException)
        {
            try { proc.Kill(entireProcessTree: true); } catch { /* already gone */ }
            if (ct.IsCancellationRequested) throw;
            throw new FetchException(FetchKind.Failed, L.Timeout((int)Timeout.TotalSeconds));
        }

        string Out() { lock (stdout) return stdout.ToString(); }
        string Err() { lock (stderr) return stderr.ToString(); }
        return ParseOutput(Out(), Err());
    }

    /// stdout is the JSON; when it is unusable, stderr is checked too (login problems print there).
    public static Snapshot ParseOutput(string stdout, string stderr, DateTimeOffset? now = null)
    {
        try { return UsageParser.Parse(stdout, now ?? DateTimeOffset.UtcNow); }
        catch (FetchException e) when (e.Kind == FetchKind.Failed && e.Message == L.EmptyOutput && stderr.Trim().Length > 0)
        {
            throw UsageParser.Classify(stderr);
        }
    }
}
