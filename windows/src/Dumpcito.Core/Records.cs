using System.Text.Json.Serialization;

namespace Dumpcito.Core;

/// Spec: spec/HOOK-SPEC.md. State the hook records for one session.
public enum HookState { Idle, Working, Waiting, Done }

public enum AgentTool { Claude, Codex, Cursor }

public static class AgentToolInfo
{
    public static string Id(this AgentTool t) => t.ToString().ToLowerInvariant();

    public static string DisplayName(this AgentTool t) => t switch
    {
        AgentTool.Claude => "Claude Code",
        AgentTool.Codex => "Codex",
        _ => "Cursor",
    };

    /// What to tell the user after connecting; null when there is nothing to add.
    public static string? ConnectNote(this AgentTool t) => t switch
    {
        AgentTool.Codex => "Open Codex and run /hooks once to trust Dumpcito. Codex skips new hooks until you do.",
        AgentTool.Cursor => "Cursor has no \"needs you\" event, so Dumpcito only tells you when a turn finishes.",
        _ => null,
    };
}

/// One state file. Times are epoch milliseconds.
public sealed class StateRecord
{
    [JsonPropertyName("v")] public int V { get; set; } = 1;
    [JsonPropertyName("tool")] public string Tool { get; set; } = "";
    [JsonPropertyName("session")] public string Session { get; set; } = "";
    [JsonPropertyName("cwd")] public string Cwd { get; set; } = "";
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("state")] public string StateName { get; set; } = "idle";
    [JsonPropertyName("at")] public long At { get; set; }
    [JsonPropertyName("workingSince")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public long? WorkingSince { get; set; }
    [JsonPropertyName("touched")] public long Touched { get; set; }

    [JsonIgnore] public string Key => $"{Tool}__{Session}";

    [JsonIgnore]
    public HookState State
    {
        get => StateName switch { "working" => HookState.Working, "waiting" => HookState.Waiting, "done" => HookState.Done, _ => HookState.Idle };
        set => StateName = value.ToString().ToLowerInvariant();
    }

    public StateRecord Clone() => (StateRecord)MemberwiseClone();
}

public abstract record HookAction
{
    public sealed record Ignore : HookAction;
    public sealed record Remove(string Tool, string Session) : HookAction;
    public sealed record Write(StateRecord Record) : HookAction;
}
