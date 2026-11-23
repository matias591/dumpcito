using System.Globalization;
using System.Text.Json;

namespace Dumpcito.Core;

/// Spec section 3. Turns one hook payload into a state-file action.
public static class HookNormalizer
{
    public static readonly HashSet<string> KnownTools = new(Enum.GetValues<AgentTool>().Select(t => t.Id()));
    static readonly HashSet<string> WaitingNotifications = new() { "permission_prompt", "elicitation_dialog", "elicitation_url_dialog" };
    static readonly HashSet<string> PromptEvents = new() { "userpromptsubmit", "beforesubmitprompt", "userpromptsubmitted" };
    static readonly HashSet<string> WorkingEvents = new(PromptEvents)
        { "pretooluse", "posttooluse", "posttoolusefailure", "permissiondenied" };

    /// Session ids become part of a file name, so anything that could escape the directory is refused.
    public static bool IsSafe(string? id) =>
        !string.IsNullOrEmpty(id) && id.Length <= 64 &&
        id.All(c => c < 128 && (char.IsLetterOrDigit(c) || c == '-' || c == '_'));

    public static string? SessionId(JsonElement payload) =>
        Str(payload, "session_id") ?? Str(payload, "sessionId") ?? Str(payload, "conversation_id");

    static string? Str(JsonElement o, string name) =>
        o.ValueKind == JsonValueKind.Object && o.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    public static HookAction Normalize(string tool, JsonElement payload, StateRecord? existing, long now)
    {
        var session = SessionId(payload);
        var rawEvent = Str(payload, "hook_event_name") ?? Str(payload, "hookEventName");
        if (!KnownTools.Contains(tool) || !IsSafe(session) || rawEvent is null) return new HookAction.Ignore();
        var ev = rawEvent.ToLowerInvariant();
        if (ev == "sessionend") return new HookAction.Remove(tool, session!);

        var current = existing?.State;
        HookState? target = null;
        if (WorkingEvents.Contains(ev)) target = HookState.Working;
        else if (ev == "permissionrequest") target = HookState.Waiting;
        else if (ev == "notification")
        {
            if (IsWaitingNotification(payload) && current != HookState.Done && current != HookState.Idle) target = HookState.Waiting;
        }
        else if (ev is "stop" or "agentstop" or "stopfailure")
        {
            target = HookState.Done;
            if (tool == "cursor" && Str(payload, "status") != "completed") target = HookState.Idle;
        }
        else if (ev == "sessionstart")
        {
            if (existing is null) target = HookState.Idle;
        }

        // Touch-only events never create a file.
        if (target is null && existing is null) return new HookAction.Ignore();

        var record = existing?.Clone() ?? new StateRecord
        {
            Tool = tool, Session = session!, State = target ?? HookState.Idle, At = now, Touched = now,
        };
        record.Touched = now;
        var cwd = Str(payload, "cwd");
        if (string.IsNullOrEmpty(cwd) && payload.ValueKind == JsonValueKind.Object &&
            payload.TryGetProperty("workspace_roots", out var roots) && roots.ValueKind == JsonValueKind.Array &&
            roots.GetArrayLength() > 0 && roots[0].ValueKind == JsonValueKind.String)
            cwd = roots[0].GetString();
        if (!string.IsNullOrEmpty(cwd)) record.Cwd = cwd;
        if (PromptEvents.Contains(ev) && Str(payload, "prompt") is { } prompt)
        {
            var collapsed = string.Join(" ", prompt.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
            if (collapsed.Length > 0) record.Title = Prefix(collapsed, 80);
        }
        if (target is not { } t || t == existing?.State) return new HookAction.Write(record);

        record.State = t;
        record.At = now;
        switch (t)
        {
            case HookState.Working or HookState.Waiting:
                record.WorkingSince = (current is HookState.Working or HookState.Waiting) ? existing?.WorkingSince ?? now : now;
                break;
            case HookState.Idle:
                record.WorkingSince = null;
                break; // Done keeps workingSince from the turn that just ended.
        }
        return new HookAction.Write(record);
    }

    static bool IsWaitingNotification(JsonElement payload)
    {
        if (Str(payload, "notification_type") is { } type) return WaitingNotifications.Contains(type);
        return Str(payload, "message")?.Contains("permission", StringComparison.OrdinalIgnoreCase) == true;
    }

    /// First n user-perceived characters (matches Swift's Character-based prefix).
    static string Prefix(string s, int n)
    {
        var e = StringInfo.GetTextElementEnumerator(s);
        var sb = new System.Text.StringBuilder();
        for (var i = 0; i < n && e.MoveNext(); i++) sb.Append((string)e.Current);
        return sb.ToString();
    }
}
