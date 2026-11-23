using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Media;
using System.Windows.Threading;
using Dumpcito.Core;
using Forms = System.Windows.Forms;

namespace Dumpcito.App;

/// The whole app: a tray icon, a 1 s poll of the state directory, alert cards and the connect window.
public sealed class TrayController : IDisposable
{
    readonly System.Windows.Application app;
    readonly Forms.NotifyIcon icon = new();
    readonly StateStore store = new();
    readonly EventDetector detector = new();
    readonly AgentConnector connector = new();
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    ConnectWindow? connectWindow;

    public TrayController(System.Windows.Application app) => this.app = app;

    public void Start()
    {
        try { store.Prune(); } catch { }
        icon.Icon = MakeIcon();
        icon.Text = "Dumpcito";
        icon.Visible = true;
        icon.ContextMenuStrip = new Forms.ContextMenuStrip();
        icon.ContextMenuStrip.Opening += (_, _) => BuildMenu();
        icon.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) ShowConnect(); };
        timer.Tick += (_, _) => Poll();
        timer.Start();
        Poll(); // priming poll: existing sessions never alert at startup

        // First run: nothing is connected yet, so open the checklist.
        if (connector.Status().All(s => !s.Connected)) ShowConnect();
    }

    void Poll()
    {
        try
        {
            var events = detector.Ingest(store.ReadAll(), DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            foreach (var e in events)
            {
                (e.Kind == DetectedKind.NeedsAttention ? SystemSounds.Exclamation : SystemSounds.Asterisk).Play();
                new AlertWindow(e).Show();
            }
        }
        catch { /* a bad poll must never crash the app */ }
    }

    void BuildMenu()
    {
        var menu = icon.ContextMenuStrip!;
        menu.Items.Clear();
        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var live = store.ReadAll().Where(r => !EventDetector.IsStale(r, now) || r.State is HookState.Done)
            .OrderByDescending(r => r.Touched).Take(6).ToList();
        if (live.Count == 0) menu.Items.Add(new Forms.ToolStripMenuItem("No active sessions") { Enabled = false });
        foreach (var r in live)
        {
            var tool = Enum.TryParse<AgentTool>(r.Tool, true, out var t) ? t.DisplayName() : r.Tool;
            var name = !string.IsNullOrWhiteSpace(r.Title) ? r.Title : System.IO.Path.GetFileName(r.Cwd.TrimEnd('/', '\\'));
            menu.Items.Add(new Forms.ToolStripMenuItem($"{tool}: {EventDetector.DisplayState(r, now).ToString().ToLowerInvariant()}  {Trim(name, 40)}") { Enabled = false });
        }
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Connect agents…", null, (_, _) => ShowConnect());
        var login = new Forms.ToolStripMenuItem("Launch at login") { Checked = AgentConnector.LaunchAtLogin, CheckOnClick = true };
        login.CheckedChanged += (_, _) => { try { AgentConnector.LaunchAtLogin = login.Checked; } catch { } };
        menu.Items.Add(login);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit Dumpcito", null, (_, _) => { icon.Visible = false; app.Shutdown(); });
    }

    static string Trim(string s, int n) => s.Length <= n ? s : s[..(n - 1)] + "…";

    void ShowConnect()
    {
        if (connectWindow is { IsLoaded: true }) { connectWindow.Activate(); return; }
        connectWindow = new ConnectWindow(connector);
        connectWindow.Closed += (_, _) => connectWindow = null;
        connectWindow.Show();
        connectWindow.Activate();
    }

    /// A small rounded dark square with a green dot, drawn in code so no asset file is needed.
    static Icon MakeIcon()
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using var bg = new SolidBrush(Color.FromArgb(0x27, 0x27, 0x2A));
            g.FillEllipse(bg, 1, 1, 30, 30);
            using var dot = new SolidBrush(Color.FromArgb(0x4A, 0xDE, 0x80));
            g.FillEllipse(dot, 9, 9, 14, 14);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    public void Dispose() { timer.Stop(); icon.Visible = false; icon.Dispose(); }
}
