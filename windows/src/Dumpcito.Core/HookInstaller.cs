using System.Text.Json;
using System.Text.Json.Nodes;

namespace Dumpcito.Core;

public sealed class HookInstallException : Exception
{
    public HookInstallException(string message) : base(message) { }
}

/// Adds or removes Dumpcito's hook entries in one tool's hook config (Claude Code, Codex or Cursor).
/// Spec: spec/HOOK-SPEC.md section 5. Consent-based: only called when the user presses Connect / Disconnect.
/// Never touches entries it did not add, keeps a timestamped backup before the first change, writes atomically.
public sealed class HookInstaller
{
    /// Entries are recognised by this substring plus our exe name, because Windows has no portable comment syntax.
    const string ArgsMarker = "--hook --tool";
    const string ExeName = "Dumpcito.exe";
    static readonly string[] LegacyMarkers = { "dumpcito-attention-hook", "buddy-attention-hook", "dumpcito-hook" };

    public static IReadOnlyList<string> Events(AgentTool tool) => tool switch
    {
        AgentTool.Claude => new[] { "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
            "PermissionRequest", "PermissionDenied", "Notification", "Stop", "StopFailure", "SessionStart", "SessionEnd" },
        AgentTool.Codex => new[] { "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionStart", "SessionEnd" },
        // Never add Cursor's permission-style hooks: invalid output from them blocks the user's action.
        _ => new[] { "beforeSubmitPrompt", "postToolUse", "stop", "sessionEnd" },
    };

    public static string DefaultConfigPath(AgentTool tool, string? home = null)
    {
        home ??= Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return tool switch
        {
            AgentTool.Claude => Path.Combine(home, ".claude", "settings.json"),
            AgentTool.Codex => Path.Combine(home, ".codex", "hooks.json"),
            _ => Path.Combine(home, ".cursor", "hooks.json"),
        };
    }

    /// True if the tool looks installed, used to pre-tick the connect list.
    public static bool IsToolPresent(AgentTool tool, string? home = null, string? localAppData = null, IEnumerable<string>? searchPath = null)
    {
        home ??= Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        localAppData ??= Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (Directory.Exists(Path.Combine(home, "." + tool.Id()))) return true;
        if (tool == AgentTool.Cursor && Directory.Exists(Path.Combine(localAppData, "Programs", "cursor"))) return true;
        searchPath ??= (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        var names = new[] { tool.Id() + ".exe", tool.Id() + ".cmd", tool.Id() };
        return searchPath.Any(d => names.Any(n => File.Exists(Path.Combine(d, n))));
    }

    public AgentTool Tool { get; }
    public string ConfigPath { get; }
    public string Executable { get; }

    public HookInstaller(AgentTool tool, string executable, string? configPath = null)
    {
        Tool = tool; Executable = executable; ConfigPath = configPath ?? DefaultConfigPath(tool);
    }

    string FileName => Path.GetFileName(ConfigPath);

    /// Forward slashes work in cmd, PowerShell and Git Bash (which Claude Code uses for hooks on Windows).
    /// The app itself forces exit code 0.
    internal string Command => $"\"{Executable.Replace('\\', '/')}\" {ArgsMarker} {Tool.Id()}";

    JsonObject Entry()
    {
        if (Tool == AgentTool.Cursor) return new JsonObject { ["command"] = Command, ["timeout"] = 5 };
        return new JsonObject
        {
            ["matcher"] = "",
            ["hooks"] = new JsonArray(new JsonObject { ["type"] = "command", ["command"] = Command, ["timeout"] = 5 }),
        };
    }

    static bool Matches(string? cmd) =>
        cmd is not null && ((cmd.Contains(ArgsMarker) && cmd.Contains(ExeName, StringComparison.OrdinalIgnoreCase)) || LegacyMarkers.Any(cmd.Contains));

    static bool IsOurs(JsonNode? item)
    {
        if (item is not JsonObject o) return false;
        if (Matches(o["command"]?.GetValue<string>())) return true;
        return o["hooks"] is JsonArray inner && inner.Any(h => h is JsonObject ho && ho["command"] is JsonValue v && v.TryGetValue<string>(out var c) && Matches(c));
    }

    static bool TryStr(JsonNode? n, out string? s) { s = null; return n is JsonValue v && v.TryGetValue(out s); }

    public bool IsInstalled()
    {
        try
        {
            var hooks = Load()["hooks"] as JsonObject;
            if (hooks is null) return false;
            return Events(Tool).All(e => hooks[e] is JsonArray a && a.Any(IsOurs) && OursPointsAt(a));
        }
        catch { return false; }
    }

    /// Also requires the entry to be for this tool (a codex entry must not count as claude's).
    bool OursPointsAt(JsonArray a) => a.Where(IsOurs).Any(n =>
        (n as JsonObject)?.ToJsonString().Contains($"{ArgsMarker} {Tool.Id()}") == true);

    public void Install()
    {
        var root = Load();
        var hooks = root["hooks"] as JsonObject ?? new JsonObject();
        var wanted = Events(Tool);
        foreach (var name in hooks.Select(kv => kv.Key).ToList())
        {
            if (wanted.Contains(name) || hooks[name] is not JsonArray old || !old.Any(IsOurs)) continue;
            Replace(hooks, name, old.Where(n => !IsOurs(n)));
        }
        foreach (var e in wanted)
        {
            var kept = (hooks[e] as JsonArray ?? new JsonArray()).Where(n => !IsOurs(n)).Select(n => n!.DeepClone()).ToList();
            kept.Add(Entry());
            hooks[e] = new JsonArray(kept.ToArray());
        }
        root["hooks"] = hooks;
        if (Tool == AgentTool.Cursor && root["version"] is null) root["version"] = 1;
        Save(root);
    }

    public void Uninstall()
    {
        var root = Load();
        if (root["hooks"] is not JsonObject hooks) return;
        foreach (var name in hooks.Select(kv => kv.Key).ToList())
            if (hooks[name] is JsonArray items) Replace(hooks, name, items.Where(n => !IsOurs(n)));
        if (hooks.Count == 0) root.Remove("hooks");
        Save(root);
    }

    static void Replace(JsonObject hooks, string name, IEnumerable<JsonNode?> kept)
    {
        var list = kept.Select(n => n!.DeepClone()).ToArray();
        if (list.Length == 0) hooks.Remove(name); else hooks[name] = new JsonArray(list);
    }

    // Files

    JsonObject Load()
    {
        if (!File.Exists(ConfigPath)) return new JsonObject();
        string text;
        try { text = File.ReadAllText(ConfigPath); }
        catch { throw new HookInstallException($"{FileName} could not be read as JSON, so Dumpcito left it untouched."); }
        if (string.IsNullOrWhiteSpace(text)) return new JsonObject();
        JsonNode? node;
        try { node = JsonNode.Parse(text, documentOptions: new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true }); }
        catch { throw new HookInstallException($"{FileName} could not be read as JSON, so Dumpcito left it untouched."); }
        return node as JsonObject ?? throw new HookInstallException($"{FileName} is not a JSON object, so Dumpcito left it untouched.");
    }

    void Save(JsonObject root)
    {
        var dir = Path.GetDirectoryName(ConfigPath)!;
        Directory.CreateDirectory(dir);
        if (File.Exists(ConfigPath))
        {
            var backup = Path.Combine(dir, $"{FileName}.dumpcito-backup-{DateTime.UtcNow:yyyyMMddTHHmmssZ}");
            if (!File.Exists(backup)) File.Copy(ConfigPath, backup);
        }
        var tmp = Path.Combine(dir, $".{FileName}.{Guid.NewGuid():N}.tmp");
        File.WriteAllText(tmp, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
        File.Move(tmp, ConfigPath, overwrite: true);
    }
}
