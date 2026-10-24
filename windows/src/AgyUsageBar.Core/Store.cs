using System.Text.Json;

namespace AgyUsageBar.Core;

/// Small JSON files under %LOCALAPPDATA%\AgyUsageBar (macOS/Linux: ~/.local/share/AgyUsageBar when run from tests).
public sealed class Store(string dir)
{
    public static string DefaultDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AgyUsageBar");

    public string Dir { get; } = dir;

    private static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public T? Read<T>(string name) where T : class
    {
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(Path.Combine(Dir, name)), Options); }
        catch { return null; }
    }

    public void Write<T>(T value, string name)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            var path = Path.Combine(Dir, name);
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(value, Options));
            File.Move(tmp, path, overwrite: true);
        }
        catch
        {
            // Persistence is best effort: the app keeps working from memory.
        }
    }
}

public sealed class Settings
{
    public DisplayChoice Choice { get; set; } = DisplayChoice.Gemini5h;

    /// "auto" | "en" | "id"
    public string Lang { get; set; } = "auto";

    /// Optional full path to agy, picked from the tray menu when it is not on PATH.
    public string? AgyPath { get; set; }
}
