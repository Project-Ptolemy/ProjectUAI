using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;

namespace ProjectUai.Bridge;

// Exercises native WPF bindings and lifecycle with an actual offline bridge.
// The windows stay offscreen, and fixtures never download or execute updates.
internal static class DesktopWindowTest
{
    internal static int Run(string output)
    {
        var application = Application.Current ?? throw new InvalidOperationException("The WPF application must exist before window verification.");
        application.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        var checks = new List<string>();
        string? failure = null;
        var bridge = new BridgeProcess();
        var window = CreateWindow(bridge);
        MainWindow activeWindow = window;
        using var instance = new DesktopInstance("ProjectUAI.Bridge.Test." + Guid.NewGuid().ToString("N"));
        int queuedRestores = 0;
        instance.RestoreExisting();
        instance.Listen(window, () => { window.RestoreWindow(); queuedRestores++; });
        var deadline = new DispatcherTimer(DispatcherPriority.Normal, application.Dispatcher) { Interval = TimeSpan.FromSeconds(55) };
        deadline.Tick += (_, _) =>
        {
            failure ??= "Window lifecycle exceeded 55 seconds.";
            deadline.Stop();
            _ = activeWindow.RequestCloseAsync();
        };
        bool started = false;
        window.Loaded += async (_, _) =>
        {
            if (started) return;
            started = true;
            try
            {
                await window.Model.InitializeAsync();
                await SettleAsync(window);
                if (!window.Model.CanStart) throw new IOException("Offline initialization did not detect the installed Node runtime.");
                if (window.Model.OpenCodeInstallation is not ("Installed" or "Not found") ||
                    window.Model.ClineInstallation is not ("Installed" or "Not found") || bridge.BrowserUrl is not null)
                    throw new IOException("Installed apps were not detected before Cowork activation.");
                if (Named<TextBlock>(window, "OpenCodeInstallationStatus").Text != window.Model.OpenCodeInstallation ||
                    Named<TextBlock>(window, "ClineInstallationStatus").Text != window.Model.ClineInstallation)
                    throw new IOException("Native installation labels are detached from detection results.");
                await window.Model.RefreshTunnelInstallationsAsync();
                if (bridge.BrowserUrl is not null) throw new IOException("Refreshing installed apps started Cowork.");
                checks.Add("Native installation status and refresh work before Cowork starts");
                var start = Named<Button>(window, "StartButton");
                var stop = Named<Button>(window, "StopButton");
                var update = Named<Button>(window, "UpdateButton");
                var startCommand = start.Command ?? throw new IOException("Start has no native command.");
                var stopCommand = stop.Command ?? throw new IOException("Stop has no native command.");
                if (!ReferenceEquals(startCommand, window.Model.StartCommand) ||
                    !ReferenceEquals(stopCommand, window.Model.StopCommand) ||
                    !ReferenceEquals(update.Command, window.Model.UpdateCommand))
                    throw new IOException("A primary action is detached from its WPF command.");
                if (!start.IsEnabled || stop.IsEnabled || !startCommand.CanExecute(start.CommandParameter))
                    throw new IOException("Idle command availability does not match the bridge state.");
                checks.Add("Native WPF start, stop, and update actions bind to their commands");

                var shortcuts = window.InputBindings.OfType<KeyBinding>().Where(binding => binding.Modifiers == ModifierKeys.Control).ToArray();
                for (int page = 0; page < 5; page++)
                {
                    var binding = shortcuts.SingleOrDefault(item => item.Key == (Key)((int)Key.D1 + page))
                        ?? throw new IOException("A desktop page shortcut is missing.");
                    if (!ReferenceEquals(binding.Command, window.Model.NavigateCommand)) throw new IOException("A page shortcut is detached from navigation.");
                    binding.Command.Execute(binding.CommandParameter);
                    if (window.Model.SelectedPage != page) throw new IOException("A page shortcut opened the wrong destination.");
                }
                window.Model.SelectedPage = 0;
                checks.Add("Ctrl+1 through Ctrl+5 use the same page navigation commands as the sidebar");

                Named<ToggleButton>(window, "OpenCodeToggle").SetCurrentValue(ToggleButton.IsCheckedProperty, false);
                Named<ToggleButton>(window, "McpToggle").SetCurrentValue(ToggleButton.IsCheckedProperty, false);
                Named<ToggleButton>(window, "ClineToggle").SetCurrentValue(ToggleButton.IsCheckedProperty, false);
                Named<ToggleButton>(window, "KiloToggle").SetCurrentValue(ToggleButton.IsCheckedProperty, false);
                await SettleAsync(window);
                if (window.Model.OpenCodeEnabled || window.Model.McpEnabled || window.Model.ClineEnabled || window.Model.KiloEnabled)
                    throw new IOException("Native connection controls did not update their preferences.");
                startCommand.Execute(start.CommandParameter);
                if (window.Model.CanStart || window.Model.CanConfigureConnections)
                    throw new IOException("Starting permits another start or connection changes.");
                await WaitUntilAsync(() => bridge.BrowserUrl is not null || bridge.State == "Could not start", TimeSpan.FromSeconds(45));
                await bridge.RefreshAsync();
                await SettleAsync(window);
                if (bridge.BrowserUrl is null || bridge.OpenCodeState != "disabled" || bridge.McpEnabled || bridge.ClineState != "disabled" || bridge.KiloState != "disabled")
                    throw new IOException("Integration switches did not reach the packaged bridge.");
                if (!window.Model.CanStop || start.IsEnabled != window.Model.CanStart || !stop.IsEnabled || window.Model.CanConfigureConnections)
                    throw new IOException("Running command availability does not match the bridge state.");
                checks.Add("Starting applies connection preferences and prevents conflicting actions");

                await WaitUntilAsync(() => queuedRestores == 1, TimeSpan.FromSeconds(3));
                if (queuedRestores != 1) throw new IOException("A duplicate launch during startup lost its restore signal.");
                checks.Add("A duplicate launch before WPF loads restores after first show");

                stopCommand.Execute(stop.CommandParameter);
                if (bridge.State != "Stopped" && (window.Model.CanStart || window.Model.CanStop || window.Model.CanConfigureConnections))
                    throw new IOException("Stopping permits a conflicting bridge action.");
                await WaitUntilAsync(() => bridge.State == "Stopped" && !window.Model.IsBusy, TimeSpan.FromSeconds(12));
                await SettleAsync(window);
                if (bridge.BrowserUrl is not null || bridge.State != "Stopped" || !window.Model.CanStart || !window.Model.CanConfigureConnections || stop.IsEnabled)
                    throw new IOException("Stop did not release the bridge and restore idle controls.");
                checks.Add("Stopping releases the bridge and restores connection settings");

                await CheckLayoutAsync(window);
                checks.Add("All five pages retain accessible, scroll-reachable actions at narrow and restored sizes");
                window.WindowState = WindowState.Minimized;
                await Task.Delay(100);
                if (!window.IsVisible || !window.ShowInTaskbar || window.WindowState != WindowState.Minimized)
                    throw new IOException("Minimize hid the native app from the taskbar.");
                window.RestoreWindow();
                await SettleAsync(window);
                if (!window.IsVisible || window.WindowState != WindowState.Normal)
                    throw new IOException("Restore did not show the app.");
                checks.Add("Minimize retains the taskbar window and restore returns the normal window");

                await window.Model.StartAsync();
                await bridge.RefreshAsync();
                if (bridge.BrowserUrl is null) throw new IOException("The stopped bridge could not restart.");
                Task closing = window.RequestCloseAsync();
                await Dispatcher.Yield(DispatcherPriority.Background);
                if (!window.Model.IsExiting || window.Model.CanStart || window.Model.CanStop || window.Model.CanUpdate || window.Model.CanConfigureConnections)
                    throw new IOException("Closing permits actions while owned bridge shutdown is pending.");
                await closing;
                if (!window.IsClosed || bridge.BrowserUrl is not null || bridge.State != "Stopped")
                    throw new IOException("Closing did not wait for owned bridge shutdown.");
                checks.Add("Closing a live window disables actions and awaits owned bridge shutdown");
                instance.RestoreExisting();
                await Task.Delay(100);
                if (queuedRestores != 1) throw new IOException("A closed window accepted a duplicate-launch restore.");
                checks.Add("A closed WPF window ignores later restore signals");
                await CheckStartingCloseAsync(next => activeWindow = next);
                checks.Add("Closing during startup cancels readiness, releases the child and port, and settles within 12 seconds");
                await CheckPendingCloseAsync(next => activeWindow = next);
                checks.Add("Ordinary close retains a staged update without launching a helper");
            }
            catch (Exception error) { failure ??= error.Message; }
            finally
            {
                deadline.Stop();
                try
                {
                    await activeWindow.RequestCloseAsync();
                    if (!ReferenceEquals(activeWindow, window)) await window.RequestCloseAsync();
                    await bridge.DisposeAsync();
                }
                catch (Exception error) { failure ??= error.Message; }
                application.Shutdown(failure is null ? 0 : 1);
            }
        };
        deadline.Start();
        window.Show();
        application.Run();
        File.WriteAllText(output, JsonSerializer.Serialize(new { ok = failure is null, checks, error = failure }, new JsonSerializerOptions { WriteIndented = true }));
        return failure is null ? 0 : 1;
    }

    private static MainWindow CreateWindow(BridgeProcess bridge, DesktopUpdater? updates = null) => new(bridge, offline: true, updates: updates)
    {
        WindowStartupLocation = WindowStartupLocation.Manual,
        Left = -30000,
        Top = -30000,
        ShowActivated = false
    };

    private static T Named<T>(MainWindow window, string name) where T : FrameworkElement =>
        window.FindName(name) as T ?? throw new IOException($"The WPF interface is missing {name}.");

    private static async Task SettleAsync(Window window)
    {
        window.UpdateLayout();
        await Dispatcher.Yield(DispatcherPriority.ContextIdle);
        window.UpdateLayout();
    }

    private static async Task WaitUntilAsync(Func<bool> ready, TimeSpan timeout)
    {
        DateTime until = DateTime.UtcNow + timeout;
        while (!ready())
        {
            if (DateTime.UtcNow >= until) throw new IOException("The native window did not settle before its deadline.");
            await Task.Delay(30);
        }
    }

    private static async Task CheckLayoutAsync(MainWindow window)
    {
        string[] pageNames = ["WorkspacePage", "ConnectionsPage", "UpdatesPage", "SettingsPage", "TunnelsPage"];
        string[] actionNames = ["StartButton", "StopButton", "UpdateButton", "BridgeUpdateButton", "InstallNodeButton", "RecheckNodeButton", "OpenCodeToggle", "McpToggle", "OpenBrowserToggle", "AutomaticUpdatesToggle", "StartOnLaunchToggle", "ClineToggle", "KiloToggle", "ClineSetupButton", "ClineSignInButton", "RefreshInstallationsButton"];
        var pages = pageNames.Select(name => Named<FrameworkElement>(window, name)).ToArray();
        var actions = actionNames.Select(name => Named<FrameworkElement>(window, name)).ToArray();
        var scroll = Named<ScrollViewer>(window, "PageScroll");
        if (actions.Any(action => string.IsNullOrWhiteSpace(AutomationProperties.GetName(action))))
            throw new IOException("A native action has no accessible name.");
        foreach (var size in new[] { new Size(640, 560), new Size(1120, 820) })
        {
            window.Width = size.Width;
            window.Height = size.Height;
            bool hadScrollRange = false;
            var reached = new HashSet<FrameworkElement>();
            for (int page = 0; page < pages.Length; page++)
            {
                window.Model.NavigateCommand.Execute(page);
                await SettleAsync(window);
                if (window.Model.SelectedPage != page || pages[page].Visibility != Visibility.Visible ||
                    pages.Where((_, index) => index != page).Any(other => other.Visibility == Visibility.Visible))
                    throw new IOException($"Page navigation did not display {pageNames[page]} alone.");
                hadScrollRange |= scroll.ScrollableHeight > 0;
                foreach (var action in actions.Where(action => action.IsVisible))
                {
                    if (action.ActualWidth <= 0 || action.ActualHeight <= 0)
                        throw new IOException($"Action {action.Name} has no native layout bounds.");
                    action.BringIntoView();
                    await SettleAsync(window);
                    Rect bounds = action.TransformToAncestor(scroll).TransformBounds(new Rect(action.RenderSize));
                    if (!new Rect(new Size(scroll.ActualWidth, scroll.ActualHeight)).IntersectsWith(bounds))
                        throw new IOException($"Action {action.Name} cannot be scrolled into view at {size.Width}x{size.Height}.");
                    reached.Add(action);
                }
            }
            if (reached.Count != actions.Length) throw new IOException("Page navigation left a required action unreachable.");
            if (size.Width < 800 && !hadScrollRange) throw new IOException("The narrow layout did not exercise native page scrolling.");
        }
        window.Model.NavigateCommand.Execute(0);
        scroll.ScrollToTop();
        await SettleAsync(window);
    }

    private static async Task CheckStartingCloseAsync(Action<MainWindow> activate)
    {
        string fixtureRoot = Path.Combine(Path.GetTempPath(), "uai-window-startup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(fixtureRoot);
        string preload = Path.Combine(fixtureRoot, "delay-start.js"), marker = Path.Combine(fixtureRoot, "child.pid");
        // Node probes remove NODE_OPTIONS. The actual child records its PID and
        // pauses before server startup, making readiness cancellation observable.
        File.WriteAllText(preload, "require('node:fs').writeFileSync(" + JsonSerializer.Serialize(marker) + ", String(process.pid));\n" +
            "Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 30000);\n");
        string? options = Environment.GetEnvironmentVariable("NODE_OPTIONS");
        await using var bridge = new BridgeProcess();
        var window = CreateWindow(bridge);
        activate(window);
        Task? starting = null;
        try
        {
            window.Show();
            await window.Model.InitializeAsync();
            if (!window.Model.CanStart) throw new IOException("Startup cancellation fixture did not detect Node.js.");
            window.Model.OpenCodeEnabled = false;
            window.Model.McpEnabled = false;
            window.Model.ClineEnabled = false;
            Environment.SetEnvironmentVariable("NODE_OPTIONS", "--require=\"" + preload.Replace('\\', '/') + "\"");
            starting = window.Model.StartAsync();
            await WaitUntilAsync(() => File.Exists(marker) && new FileInfo(marker).Length > 0, TimeSpan.FromSeconds(15));
            int pid = int.Parse(await File.ReadAllTextAsync(marker));
            using var child = Process.GetProcessById(pid);
            _ = child.Handle; // Retain the exact process even if its PID is reused.
            if (starting.IsCompleted || bridge.State != "Starting" || bridge.BrowserUrl is not null || child.HasExited)
                throw new IOException("The startup cancellation fixture did not pause an owned child before readiness.");
            var elapsed = Stopwatch.StartNew();
            Task closing = window.RequestCloseAsync();
            await Dispatcher.Yield(DispatcherPriority.Background);
            if (!window.Model.IsExiting || window.Model.CanStart || window.Model.CanStop || window.Model.CanConfigureConnections)
                throw new IOException("Closing during startup did not disable conflicting actions.");
            await Task.WhenAll(starting, closing).WaitAsync(TimeSpan.FromSeconds(12));
            if (elapsed.Elapsed > TimeSpan.FromSeconds(12) || !window.IsClosed || bridge.State != "Stopped" || bridge.BrowserUrl is not null || !child.HasExited)
                throw new IOException("Closing during startup left the window, token, or owned child alive.");
            // Local firewall software can delay a refused loopback connect past any
            // small deadline. The active-listener table answers without a handshake.
            var globals = System.Net.NetworkInformation.IPGlobalProperties.GetIPGlobalProperties();
            DateTime portDeadline = DateTime.UtcNow + TimeSpan.FromSeconds(3);
            while (globals.GetActiveTcpListeners().Any(endpoint => endpoint.Port == BridgeProcess.Port))
            {
                if (DateTime.UtcNow >= portDeadline) throw new IOException("Closing during startup left the bridge port listening.");
                await Task.Delay(100);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable("NODE_OPTIONS", options);
            await window.RequestCloseAsync();
            if (starting is not null) await starting;
            UpdateFiles.RemoveOwnedDirectory(Path.GetTempPath(), fixtureRoot);
        }
    }

    private static async Task CheckPendingCloseAsync(Action<MainWindow> activate)
    {
        string fixtureRoot = Path.Combine(Path.GetTempPath(), "uai-window-update-" + Guid.NewGuid().ToString("N"));
        try
        {
            string cache = Path.Combine(fixtureRoot, "cache");
            var current = Version.Parse(DesktopUpdater.CurrentVersion);
            string version = new Version(current.Major, current.Minor + 1, 0).ToString();
            byte[] bytes = Encoding.UTF8.GetBytes("MZ synthetic update: must never launch");
            byte[] manifest = JsonSerializer.SerializeToUtf8Bytes(new
            {
                format = "project-uai-desktop-release", schema = 1, version, platform = "win-x64", protocol = 1,
                package = new { name = $"UAI-Bridge-{version}-win-x64.exe", bytes = bytes.Length, sha256 = UpdateFiles.Hash(bytes) }
            });
            var staging = new DesktopUpdater(fixtureRoot, cacheDirectory: cache);
            string key = staging.Stage(manifest, bytes);
            string pending = Path.Combine(cache, "pending.json");
            UpdateFiles.AtomicJson(pending, new { key });
            var ready = new DesktopUpdater(fixtureRoot, cacheDirectory: cache);
            if (!ready.ReadyToRestart) throw new IOException("Pending update fixture did not stage.");
            await using var idleBridge = new BridgeProcess();
            var idle = CreateWindow(idleBridge, ready);
            activate(idle);
            try
            {
                idle.Show();
                await idle.Model.InitializeAsync();
                await SettleAsync(idle);
                if (!idle.Model.IsUpdateReady || !idle.Model.CanUpdate || !Named<Button>(idle, "UpdateButton").IsEnabled)
                    throw new IOException("The native update page did not restore its pending update action.");
                idle.Close();
                await WaitUntilAsync(() => idle.IsClosed, TimeSpan.FromSeconds(12));
                if (!ready.ReadyToRestart || !File.Exists(pending) || Directory.GetFiles(cache, ".request-*").Length != 0)
                    throw new IOException("Normal close consumed or launched the staged update.");
            }
            finally { await idle.RequestCloseAsync(); }
        }
        finally { UpdateFiles.RemoveOwnedDirectory(Path.GetTempPath(), fixtureRoot); }
    }
}
