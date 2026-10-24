using System.Globalization;
using System.Text.Json;

namespace AgyUsageBar.Core;

/// Parses `agy -p "/usage" --output-format json`.
public static class UsageParser
{
    public static Snapshot Parse(string json, DateTimeOffset now)
    {
        JsonDocument doc;
        try { doc = JsonDocument.Parse(json); }
        catch (JsonException) { throw Classify(Head(json, 300)); }

        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw Classify(Head(json, 300));

            var status = Str(root, "status");
            var response = Str(root, "response");
            if (status is not null && status != "SUCCESS") throw Classify(response ?? status);

            if (!root.TryGetProperty("command", out var cmd) || cmd.ValueKind != JsonValueKind.Object
                || !cmd.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Object
                || !data.TryGetProperty("groups", out var groups) || groups.ValueKind != JsonValueKind.Array
                || groups.GetArrayLength() == 0)
                throw Classify(response ?? "");

            var parsed = new List<UsageGroup>();
            foreach (var g in groups.EnumerateArray())
            {
                var buckets = new List<Bucket>();
                if (g.TryGetProperty("buckets", out var bs) && bs.ValueKind == JsonValueKind.Array)
                {
                    foreach (var b in bs.EnumerateArray())
                    {
                        var id = Str(b, "id");
                        if (id is null || !b.TryGetProperty("remaining_fraction", out var rf) || rf.ValueKind != JsonValueKind.Number) continue;
                        var window = Str(b, "window") ?? (id.EndsWith("5h", StringComparison.Ordinal) ? "5h" : "weekly");
                        var fallback = now + (window == "5h" ? TimeSpan.FromHours(5) : TimeSpan.FromDays(7));
                        buckets.Add(new Bucket(id, window, rf.GetDouble(), ParseDate(Str(b, "reset_time")) ?? fallback));
                    }
                }
                parsed.Add(new UsageGroup(Str(g, "name") ?? "", ModelsOf(Str(g, "description")), buckets));
            }
            if (!parsed.Any(g => g.Buckets.Count > 0)) throw new FetchException(FetchKind.Failed, L.Unreadable);
            return new Snapshot(now, parsed);
        }
    }

    public static FetchException Classify(string text)
    {
        var t = text.ToLowerInvariant();
        string[] auth = ["sign in", "sign-in", "log in", "login", "authenticat", "unauthorized", "credential"];
        if (auth.Any(t.Contains)) return new FetchException(FetchKind.NotSignedIn, L.NotSignedIn);
        var first = text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
        return new FetchException(FetchKind.Failed, first.Length == 0 ? L.EmptyOutput : Head(first, 120));
    }

    public static DateTimeOffset? ParseDate(string? s) =>
        s is not null && DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var d)
            ? d : null;

    private static string ModelsOf(string? description)
    {
        if (description is null) return "";
        var i = description.IndexOf(':');
        return (i >= 0 ? description[(i + 1)..] : description).Trim();
    }

    private static string? Str(JsonElement e, string name) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static string Head(string s, int n) => s.Length <= n ? s : s[..n];
}
