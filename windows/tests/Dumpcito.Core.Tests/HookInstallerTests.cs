using System.Text.Json.Nodes;
using Dumpcito.Core;
using Xunit;

namespace Dumpcito.Core.Tests;

public class HookInstallerTests : IDisposable
{
    readonly string dir = Path.Combine(Path.GetTempPath(), "hooktest-" + Guid.NewGuid().ToString("N"));
    const string Exe = @"C:\Users\me\AppData\Local\Dumpcito\Dumpcito.exe";
    public HookInstallerTests() => Directory.CreateDirectory(dir);
    public void Dispose() { try { Directory.Delete(dir, true); } catch { } }

    string Cfg => Path.Combine(dir, "settings.json");
    HookInstaller Inst(AgentTool t = AgentTool.Claude, string exe = Exe) => new(t, exe, Cfg);
    JsonObject Read() => JsonNode.Parse(File.ReadAllText(Cfg))!.AsObject();

    [Fact]
    public void InstallIntoMissingFileWritesAllEvents()
    {
        Inst().Install();
        Assert.True(Inst().IsInstalled());
        Assert.Equal(HookInstaller.Events(AgentTool.Claude).Order(), Read()["hooks"]!.AsObject().Select(kv => kv.Key).Order());
        var cmd = (string)Read()["hooks"]!["Stop"]![0]!["hooks"]![0]!["command"]!;
        Assert.Equal("\"C:/Users/me/AppData/Local/Dumpcito/Dumpcito.exe\" --hook --tool claude", cmd);
    }

    [Fact]
    public void KeepsOtherHooksAndSettingsAndBacksUp()
    {
        var original = """{"model":"x","hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"echo hi"}]}]}}""";
        File.WriteAllText(Cfg, original);
        Inst().Install();
        Assert.Equal("x", (string)Read()["model"]!);
        Assert.Equal(2, Read()["hooks"]!["Stop"]!.AsArray().Count);
        var backups = Directory.GetFiles(dir).Where(f => f.Contains("dumpcito-backup")).ToList();
        Assert.Single(backups);
        Assert.Equal(original, File.ReadAllText(backups[0]));
    }

    [Fact]
    public void IdempotentAndUpdatesPath()
    {
        Inst(exe: @"C:\old\Dumpcito.exe").Install();
        Inst(exe: @"C:\new\Dumpcito.exe").Install();
        var stop = Read()["hooks"]!["Stop"]!.AsArray();
        Assert.Single(stop);
        Assert.Contains("/new/", (string)stop[0]!["hooks"]![0]!["command"]!);
    }

    [Fact]
    public void UninstallRemovesOnlyOurs()
    {
        File.WriteAllText(Cfg, """{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"echo hi"}]}]}}""");
        Inst().Install();
        Inst().Uninstall();
        Assert.False(Inst().IsInstalled());
        var hooks = Read()["hooks"]!.AsObject();
        Assert.Equal(new[] { "Stop" }, hooks.Select(kv => kv.Key));
        Assert.Single(hooks["Stop"]!.AsArray());
    }

    [Fact]
    public void RefusesCorruptSettingsAndLeavesThemAlone()
    {
        File.WriteAllText(Cfg, "{ not json");
        Assert.Throws<HookInstallException>(() => Inst().Install());
        Assert.Equal("{ not json", File.ReadAllText(Cfg));
        File.WriteAllText(Cfg, "[1,2]");
        Assert.Throws<HookInstallException>(() => Inst().Install());
    }

    [Fact]
    public void CursorUsesFlatShapeVersionAndOnlySafeEvents()
    {
        File.WriteAllText(Cfg, """{"version":1,"hooks":{"beforeShellExecution":[{"command":"./audit.sh"}],"stop":[{"command":"./mine.sh"}]}}""");
        var inst = Inst(AgentTool.Cursor);
        inst.Install();
        var hooks = Read()["hooks"]!.AsObject();
        Assert.Equal(HookInstaller.Events(AgentTool.Cursor).Append("beforeShellExecution").Order(), hooks.Select(kv => kv.Key).Order());
        Assert.Single(hooks["beforeShellExecution"]!.AsArray());
        Assert.Equal(2, hooks["stop"]!.AsArray().Count);
        inst.Uninstall();
        Assert.False(inst.IsInstalled());
        Assert.Equal(new[] { "beforeShellExecution", "stop" }, Read()["hooks"]!.AsObject().Select(kv => kv.Key).Order());
    }

    [Fact]
    public void ToolsDoNotRecogniseEachOthersEntries()
    {
        Inst(AgentTool.Codex).Install();
        Assert.False(Inst(AgentTool.Claude).IsInstalled());
        Assert.True(Inst(AgentTool.Codex).IsInstalled());
    }

    [Fact]
    public void ToolPresenceFromHomeFolder()
    {
        Assert.False(HookInstaller.IsToolPresent(AgentTool.Codex, dir, dir, Array.Empty<string>()));
        Directory.CreateDirectory(Path.Combine(dir, ".codex"));
        Assert.True(HookInstaller.IsToolPresent(AgentTool.Codex, dir, dir, Array.Empty<string>()));
    }
}
