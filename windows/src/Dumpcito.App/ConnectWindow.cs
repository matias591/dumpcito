using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Dumpcito.Core;

namespace Dumpcito.App;

/// The connect checklist: one row per tool with Connect / Disconnect and a live "working" tick.
public sealed class ConnectWindow : Window
{
    readonly AgentConnector connector;
    readonly StackPanel list = new();
    readonly TextBlock message = new() { Foreground = new SolidColorBrush(Color.FromRgb(0xA1, 0xA1, 0xAA)), FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0) };
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI");

    public ConnectWindow(AgentConnector connector)
    {
        this.connector = connector;
        Title = "Dumpcito: connect your agents"; Width = 480; SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = new SolidColorBrush(Color.FromRgb(0x18, 0x18, 0x1B)); FontFamily = Font;

        var root = new StackPanel { Margin = new Thickness(28, 24, 28, 24) };
        root.Children.Add(new TextBlock { Text = "Know when your agents need you", Foreground = Brushes.White, FontSize = 20, FontWeight = FontWeights.SemiBold });
        root.Children.Add(new TextBlock
        {
            Text = "Connecting adds a small hook to each tool's hook file. A backup is kept, nothing else in the file changes, and you can disconnect here any time. A tick means Dumpcito saw that tool send an event.",
            Foreground = new SolidColorBrush(Color.FromRgb(0xA1, 0xA1, 0xAA)), FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 16),
        });
        root.Children.Add(list); root.Children.Add(message);
        Content = root;

        timer.Tick += (_, _) => Refresh();
        Loaded += (_, _) => { Refresh(); timer.Start(); };
        Closed += (_, _) => timer.Stop();
    }

    void Refresh()
    {
        list.Children.Clear();
        foreach (var s in connector.Status()) list.Children.Add(Row(s));
    }

    UIElement Row(ToolStatus s)
    {
        var detail = s.Connected
            ? (s.Active ? "Working. Dumpcito saw it send an event." : s.Tool.ConnectNote() ?? "Connected. Start a session to confirm.")
            : (s.Present ? "Found on this PC" : "Not found on this PC");
        var texts = new StackPanel();
        texts.Children.Add(new TextBlock { Text = (s.Active ? "✓  " : "") + s.Tool.DisplayName(), Foreground = Brushes.White, FontSize = 14, FontWeight = FontWeights.SemiBold });
        texts.Children.Add(new TextBlock { Text = detail, Foreground = new SolidColorBrush(Color.FromRgb(0xA1, 0xA1, 0xAA)), FontSize = 12, TextWrapping = TextWrapping.Wrap, MaxWidth = 290, Margin = new Thickness(0, 2, 0, 0) });

        var button = new Button
        {
            Content = s.Connected ? "Disconnect" : "Connect", Padding = new Thickness(14, 6, 14, 6), MinWidth = 96,
            VerticalAlignment = VerticalAlignment.Center,
        };
        button.Click += (_, _) =>
        {
            var error = s.Connected ? connector.Disconnect(s.Tool) : connector.Connect(s.Tool);
            message.Text = error ?? (s.Connected ? $"Disconnected from {s.Tool.DisplayName()}." : s.Tool.ConnectNote() ?? $"Connected to {s.Tool.DisplayName()}.");
            Refresh();
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(texts); Grid.SetColumn(button, 1); grid.Children.Add(button);
        return new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(0x27, 0x27, 0x2A)), CornerRadius = new CornerRadius(12),
            Padding = new Thickness(16, 12, 16, 12), Margin = new Thickness(0, 0, 0, 10), Child = grid,
        };
    }
}
