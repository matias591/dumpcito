using System.Text.Json;

namespace Dumpcito.Core;

/// The state directory: one small JSON file per session, written atomically.
public sealed class StateStore
{
    public static string DefaultDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dumpcito", "state");
    public string Dir { get; }
    public StateStore(string? dir = null) => Dir = dir ?? DefaultDir;

    string PathFor(string tool, string session) => Path.Combine(Dir, $"{tool}__{session}.json");

    public StateRecord? Read(string tool, string session) => Decode(PathFor(tool, session));

    public List<StateRecord> ReadAll()
    {
        if (!Directory.Exists(Dir)) return new();
        return Directory.EnumerateFiles(Dir, "*.json").Where(f => !Path.GetFileName(f).StartsWith('.'))
            .Select(Decode).OfType<StateRecord>().ToList();
    }

    public void Write(StateRecord record)
    {
        Directory.CreateDirectory(Dir);
        var tmp = Path.Combine(Dir, $".{record.Key}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(tmp, JsonSerializer.SerializeToUtf8Bytes(record));
            File.Move(tmp, PathFor(record.Tool, record.Session), overwrite: true);
        }
        catch { try { File.Delete(tmp); } catch { } throw; }
    }

    public void Remove(string tool, string session) { try { File.Delete(PathFor(tool, session)); } catch { } }

    /// Deletes files untouched for `days` days.
    public void Prune(int days = 7, DateTimeOffset? now = null)
    {
        var cutoff = (now ?? DateTimeOffset.UtcNow).ToUnixTimeMilliseconds() - days * 86_400_000L;
        foreach (var r in ReadAll().Where(r => r.Touched < cutoff)) Remove(r.Tool, r.Session);
    }

    /// Applies a normalised action. Never throws: a hook must not fail loudly.
    public void Apply(HookAction action)
    {
        try
        {
            switch (action)
            {
                case HookAction.Remove r: Remove(r.Tool, r.Session); break;
                case HookAction.Write w: Write(w.Record); break;
            }
        }
        catch { }
    }

    static StateRecord? Decode(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || info.Length > 64 * 1024) return null;
            var r = JsonSerializer.Deserialize<StateRecord>(File.ReadAllBytes(path));
            return r is { V: 1 } && HookNormalizer.IsSafe(r.Session) && HookNormalizer.KnownTools.Contains(r.Tool) ? r : null;
        }
        catch { return null; }
    }
}

/// `Dumpcito.exe --hook --tool <tool>`: the command the AI tools run. Never fails loudly and never prints
/// anything except `{}` for Cursor (whose hooks expect JSON on stdout).
public static class AttentionHook
{
    public static void Handle(string tool, byte[] input, StateStore? store = null, DateTimeOffset? now = null)
    {
        try
        {
            if (input.Length > 1_000_000) return;
            using var doc = JsonDocument.Parse(input);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return;
            store ??= new StateStore();
            var ms = (now ?? DateTimeOffset.UtcNow).ToUnixTimeMilliseconds();
            var id = HookNormalizer.SessionId(doc.RootElement);
            var existing = HookNormalizer.IsSafe(id) ? store.Read(tool, id!) : null;
            store.Apply(HookNormalizer.Normalize(tool, doc.RootElement, existing, ms));
        }
        catch { }
    }

    public static void RunFromStdin(string tool)
    {
        try
        {
            using var ms = new MemoryStream();
            Console.OpenStandardInput().CopyTo(ms);
            Handle(tool, ms.ToArray());
            if (tool == "cursor") { using var o = Console.OpenStandardOutput(); o.Write("{}\n"u8); }
        }
        catch { }
    }
}
