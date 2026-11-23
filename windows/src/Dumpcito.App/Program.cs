using System;
using System.Linq;
using System.Threading;
using Dumpcito.Core;

namespace Dumpcito.App;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        // `Dumpcito.exe --hook --tool <tool>`: the command the AI tools run. Never shows a window, always exits 0.
        if (args.Contains("--hook"))
        {
            var i = Array.IndexOf(args, "--tool");
            var tool = i >= 0 && i + 1 < args.Length ? args[i + 1] : "claude";
            AttentionHook.RunFromStdin(tool);
            return 0;
        }

        using var single = new Mutex(true, @"Local\Dumpcito.SingleInstance", out var first);
        if (!first) return 0;

        var app = new System.Windows.Application { ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown };
        using var tray = new TrayController(app);
        tray.Start();
        return app.Run();
    }
}
