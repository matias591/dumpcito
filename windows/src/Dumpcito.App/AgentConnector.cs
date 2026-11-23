using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Dumpcito.Core;
using Microsoft.Win32;

namespace Dumpcito.App;

public sealed record ToolStatus(AgentTool Tool, bool Present, bool Connected, bool Active);

/// Connects and disconnects the AI tools, and answers the live test ("has this tool sent an event yet?").
public sealed class AgentConnector
{
    /// Hooks point at a stable copy so they keep working if the user deletes the downloaded file.
    public static string InstalledExe => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Dumpcito", "Dumpcito.exe");

    readonly StateStore store = new();
    readonly Dictionary<AgentTool, long> connectedAt = new();

    string EnsureStableCopy()
    {
        var current = Environment.ProcessPath ?? InstalledExe;
        var target = InstalledExe;
        if (string.Equals(Path.GetFullPath(current), Path.GetFullPath(target), StringComparison.OrdinalIgnoreCase)) return target;
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        try { File.Copy(current, target, overwrite: true); } catch (IOException) { /* target is running or locked: keep the existing copy */ }
        return File.Exists(target) ? target : current;
    }

    public IReadOnlyList<ToolStatus> Status()
    {
        var records = store.ReadAll();
        var exe = Environment.ProcessPath ?? InstalledExe;
        return Enum.GetValues<AgentTool>().Select(t =>
        {
            var installed = new HookInstaller(t, exe).IsInstalled();
            var since = connectedAt.TryGetValue(t, out var s) ? s : 0;
            var active = installed && records.Any(r => r.Tool == t.Id() && r.Touched > since);
            return new ToolStatus(t, HookInstaller.IsToolPresent(t), installed, active);
        }).ToList();
    }

    /// Returns an error message, or null on success.
    public string? Connect(AgentTool tool)
    {
        try
        {
            new HookInstaller(tool, EnsureStableCopy()).Install();
            connectedAt[tool] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            return null;
        }
        catch (Exception e) { return e.Message; }
    }

    public string? Disconnect(AgentTool tool)
    {
        try
        {
            new HookInstaller(tool, Environment.ProcessPath ?? InstalledExe).Uninstall();
            connectedAt.Remove(tool);
            return null;
        }
        catch (Exception e) { return e.Message; }
    }

    // Launch at login: a per-user Run key, no admin rights.
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool LaunchAtLogin
    {
        get { using var k = Registry.CurrentUser.OpenSubKey(RunKey); return k?.GetValue("Dumpcito") is string; }
        set
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) k.SetValue("Dumpcito", $"\"{Environment.ProcessPath}\"");
            else k.DeleteValue("Dumpcito", throwOnMissingValue: false);
        }
    }
}
