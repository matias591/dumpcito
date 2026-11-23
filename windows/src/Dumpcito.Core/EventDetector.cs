namespace Dumpcito.Core;

public enum DetectedKind { NeedsAttention, Finished }

public sealed record DetectedEvent(DetectedKind Kind, StateRecord Record);

/// Spec section 4. Turns successive snapshots of the state directory into alerts. Alerts come only from
/// state changes the hook recorded; there is no guessing.
public sealed class EventDetector
{
    public const double StaleAfterSeconds = 15 * 60;

    public double FinishedThreshold { get; set; }
    public double AttentionCooldown { get; set; }
    Dictionary<string, long> lastSeenAt = new();
    Dictionary<string, long> lastAttentionAlert = new();
    bool primed;

    public EventDetector(double finishedThreshold = 20, double attentionCooldown = 30)
    { FinishedThreshold = finishedThreshold; AttentionCooldown = attentionCooldown; }

    public static bool IsStale(StateRecord r, long nowMs) => (nowMs - r.Touched) / 1000.0 > StaleAfterSeconds;

    /// The state the UI shows: a record nobody touched for 15 minutes is idle.
    public static HookState DisplayState(StateRecord r, long nowMs) =>
        IsStale(r, nowMs) && (r.State is HookState.Working or HookState.Waiting) ? HookState.Idle : r.State;

    public List<DetectedEvent> Ingest(IEnumerable<StateRecord> records, long nowMs)
    {
        var events = new List<DetectedEvent>();
        var seen = new Dictionary<string, long>();
        foreach (var r in records)
        {
            var key = r.Key;
            seen[key] = r.At;
            if (!primed || IsStale(r, nowMs)) continue;
            var previous = lastSeenAt.TryGetValue(key, out var p) ? p : long.MinValue;
            if (r.At <= previous) continue;
            switch (r.State)
            {
                case HookState.Waiting:
                    if (!lastAttentionAlert.TryGetValue(key, out var last) || (nowMs - last) / 1000.0 > AttentionCooldown)
                    {
                        lastAttentionAlert[key] = nowMs;
                        events.Add(new(DetectedKind.NeedsAttention, r));
                    }
                    break;
                case HookState.Done:
                    if (r.WorkingSince is { } start && (r.At - start) / 1000.0 >= FinishedThreshold)
                        events.Add(new(DetectedKind.Finished, r));
                    break;
            }
        }
        lastSeenAt = seen;
        lastAttentionAlert = lastAttentionAlert.Where(kv => seen.ContainsKey(kv.Key)).ToDictionary(kv => kv.Key, kv => kv.Value);
        primed = true;
        return events;
    }
}
