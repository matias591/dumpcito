using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Dumpcito.Core;

namespace Dumpcito.App;

/// A small dark card in the bottom-right corner. Never steals focus; click it to dismiss.
public sealed class AlertWindow : Window
{
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(8) };

    public AlertWindow(DetectedEvent e)
    {
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; Topmost = true; ShowActivated = false; ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.WidthAndHeight;

        var tool = Enum.TryParse<AgentTool>(e.Record.Tool, true, out var t) ? t.DisplayName() : e.Record.Tool;
        var needs = e.Kind == DetectedKind.NeedsAttention;
        var headline = needs ? $"{tool} needs you" : $"{tool} finished";
        var detail = !string.IsNullOrWhiteSpace(e.Record.Title) ? e.Record.Title
            : !string.IsNullOrWhiteSpace(e.Record.Cwd) ? System.IO.Path.GetFileName(e.Record.Cwd.TrimEnd('/', '\\')) : "";

        var dot = new System.Windows.Shapes.Ellipse
        {
            Width = 10, Height = 10, Margin = new Thickness(0, 5, 12, 0), VerticalAlignment = VerticalAlignment.Top,
            Fill = new SolidColorBrush(needs ? Color.FromRgb(0xFF, 0xB8, 0x4D) : Color.FromRgb(0x4A, 0xDE, 0x80)),
        };
        var text = new StackPanel();
        text.Children.Add(new TextBlock { Text = headline, Foreground = Brushes.White, FontSize = 15, FontWeight = FontWeights.SemiBold, FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI") });
        if (detail.Length > 0)
            text.Children.Add(new TextBlock { Text = detail, Foreground = new SolidColorBrush(Color.FromRgb(0xA1, 0xA1, 0xAA)), FontSize = 12, MaxWidth = 280, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 2, 0, 0), FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI") });
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(dot); row.Children.Add(text);

        Content = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0xEE, 0x18, 0x18, 0x1B)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF)), BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14), Padding = new Thickness(18, 14, 22, 14), Margin = new Thickness(12),
            Child = row, Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 18, ShadowDepth = 2, Opacity = 0.35 },
        };

        MouseLeftButtonUp += (_, _) => Close();
        Loaded += (_, _) =>
        {
            var area = SystemParameters.WorkArea;
            Left = area.Right - ActualWidth - 8; Top = area.Bottom - ActualHeight - 8;
            timer.Start();
        };
        timer.Tick += (_, _) => { timer.Stop(); Close(); };
        Closed += (_, _) => timer.Stop();
    }
}
