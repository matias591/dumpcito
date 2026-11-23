using System.Text.Json;
using Dumpcito.Core;
using Xunit;

namespace Dumpcito.Core.Tests;

/// Replays every spec/scenarios/*.json through the real normalizer, state store and detector.
/// The macOS app runs the same files, so both apps behave identically.
public class ScenarioReplayTests
{
    const long Base = 1_800_000_000_000;

    public static IEnumerable<object[]> Files() =>
        Directory.GetFiles(Path.Combine(AppContext.BaseDirectory, "scenarios"), "*.json").OrderBy(f => f).Select(f => new object[] { Path.GetFileName(f) });

    [Fact]
    public void AllSixteenScenariosPresent() => Assert.True(Files().Count() >= 16);

    [Theory, MemberData(nameof(Files))]
    public void Replay(string file)
    {
        var scenario = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "scenarios", file))).RootElement;
        var dir = Path.Combine(Path.GetTempPath(), "scn-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new StateStore(dir);
            var detector = new EventDetector(20, 30);

            if (scenario.TryGetProperty("preseed", out var seed))
                foreach (var raw in seed.EnumerateArray())
                {
                    var r = JsonSerializer.Deserialize<StateRecord>(raw.GetRawText())!;
                    r.At += Base; r.Touched += Base;
                    if (r.WorkingSince is { } w) r.WorkingSince = w + Base;
                    store.Write(r);
                }
            detector.Ingest(store.ReadAll(), Base); // priming poll

            var i = 0;
            foreach (var step in scenario.GetProperty("steps").EnumerateArray())
            {
                var t = Base + (long)(step.GetProperty("t").GetDouble() * 1000);
                var label = $"{file} step {i++}";
                if (step.TryGetProperty("tool", out var tool) && tool.ValueKind == JsonValueKind.String &&
                    step.TryGetProperty("payload", out var payload) && payload.ValueKind == JsonValueKind.Object)
                    AttentionHook.Handle(tool.GetString()!, System.Text.Encoding.UTF8.GetBytes(payload.GetRawText()), store, DateTimeOffset.FromUnixTimeMilliseconds(t));

                var got = new List<string>();
                if (!(step.TryGetProperty("noPoll", out var np) && np.GetBoolean()))
                    got = detector.Ingest(store.ReadAll(), t).Select(e => $"{(e.Kind == DetectedKind.NeedsAttention ? "needsAttention" : "finished")}|{e.Record.Tool}|{e.Record.Session}").ToList();
                var want = new List<string>();
                if (step.TryGetProperty("expectEvents", out var ee))
                    want = ee.EnumerateArray().Select(e => $"{e.GetProperty("kind").GetString()}|{e.GetProperty("tool").GetString()}|{e.GetProperty("session").GetString()}").ToList();
                Assert.True(got.Order().SequenceEqual(want.Order()), $"{label}: events got [{string.Join(", ", got)}] want [{string.Join(", ", want)}]");

                if (step.TryGetProperty("expectState", out var es))
                    foreach (var kv in es.EnumerateObject())
                    {
                        var parts = kv.Name.Split("__");
                        var rec = store.Read(parts[0], parts[1]);
                        var shown = rec is null ? "absent" : EventDetector.DisplayState(rec, t).ToString().ToLowerInvariant();
                        Assert.True(shown == kv.Value.GetString(), $"{label}: state of {kv.Name} was {shown}, want {kv.Value.GetString()}");
                    }
            }
        }
        finally { try { Directory.Delete(dir, true); } catch { } }
    }
}
